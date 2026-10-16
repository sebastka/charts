{{/* Chart name */}}
{{- define "paperless.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Full name: the release name alone when it already contains the chart name */}}
{{- define "paperless.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Name of a component's resources: (list $ "tika") */}}
{{- define "paperless.componentName" -}}
{{- $ctx := index . 0 }}
{{- printf "%s-%s" (include "paperless.fullname" $ctx | trunc 56 | trimSuffix "-") (index . 1) }}
{{- end }}

{{/* Component metadata: app.kubernetes.io/name and component of each part */}}
{{- define "paperless.components" -}}
paperless: {name: paperless, component: document-management}
tika: {name: tika, component: content-extraction}
gotenberg: {name: gotenberg, component: document-conversion}
valkey: {name: valkey, component: key-value-store}
{{- end }}

{{/* Selector labels: (list $ "tika"). Selectors are immutable: never add to them */}}
{{- define "paperless.selectorLabels" -}}
{{- $ctx := index . 0 }}
{{- $component := index (include "paperless.components" $ctx | fromYaml) (index . 1) -}}
app.kubernetes.io/name: {{ $component.name }}
app.kubernetes.io/instance: {{ $ctx.Release.Name }}
{{- end }}

{{/* Labels: (list $ "tika") */}}
{{- define "paperless.labels" -}}
{{- $ctx := index . 0 }}
{{- $component := index (include "paperless.components" $ctx | fromYaml) (index . 1) -}}
{{ include "paperless.selectorLabels" . }}
app.kubernetes.io/component: {{ $component.component }}
app.kubernetes.io/part-of: {{ include "paperless.name" $ctx }}
app.kubernetes.io/managed-by: {{ $ctx.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" $ctx.Chart.Name $ctx.Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- with $ctx.Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Pod template labels: (list $ "tika"). Without helm.sh/chart, whose version would restart every pod on
every chart release, an image bump of another component included
*/}}
{{- define "paperless.podLabels" -}}
{{- $ctx := index . 0 }}
{{- $component := index (include "paperless.components" $ctx | fromYaml) (index . 1) -}}
{{ include "paperless.selectorLabels" . }}
app.kubernetes.io/component: {{ $component.component }}
app.kubernetes.io/part-of: {{ include "paperless.name" $ctx }}
{{- with $ctx.Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* Checksum of what the ConfigMaps hold, not of their metadata (which carries the chart version) */}}
{{- define "paperless.configChecksum" -}}
{{- list
  (include "paperless.env" .)
  (.Files.Get "files/scripts/worker-health.py")
  (ternary (.Files.Get "files/scripts/paperless-ai-review.py") "" .Values.paperless.aiReviewScript)
  (ternary (.Files.Get "files/settings/webserver.py") "" .Values.paperless.webserver.customSettings)
  (toYaml .Values.paperless.scripts)
  | join "\n" | sha256sum }}
{{- end }}

{{/* Image reference: (list $ .Values.image). The tag may carry a digest (tag@sha256:...) */}}
{{- define "paperless.image" -}}
{{- $ctx := index . 0 }}
{{- $image := index . 1 }}
{{- printf "%s:%s" $image.repository (default $ctx.Chart.AppVersion $image.tag) }}
{{- end }}

{{- define "paperless.serviceAccountName" -}}
{{- if .Values.paperless.serviceAccount.create }}
{{- default (include "paperless.fullname" .) .Values.paperless.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.paperless.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "paperless.pvcName" -}}
{{- default (printf "%s-data" (include "paperless.fullname" .)) .Values.persistence.existingClaim }}
{{- end }}

{{/* Fails on combinations that would deploy a broken paperless */}}
{{- define "paperless.validate" -}}
{{- if ne .Values.tika.enabled .Values.gotenberg.enabled }}
{{- fail "tika.enabled and gotenberg.enabled go together: paperless's Tika support needs both" }}
{{- end }}
{{- end }}

{{/* The environment of paperless: what the chart sets, then paperless.env over it, as a dict of strings */}}
{{- define "paperless.env" -}}
{{- $env := dict
  "PAPERLESS_DATA_DIR" "/usr/src/paperless/data"
  "PAPERLESS_MEDIA_ROOT" "/usr/src/paperless/media"
  "PAPERLESS_CONSUMPTION_DIR" "/usr/src/paperless/consume"
  "PAPERLESS_EMPTY_TRASH_DIR" "/usr/src/paperless/media/trash"
  "TESSDATA_PREFIX" "/mnt/tessdata"
  "PAPERLESS_BIND_ADDR" "0.0.0.0"
  "PAPERLESS_PORT" "8000"
  "GRANIAN_HOST" "0.0.0.0"
  "GRANIAN_PORT" "8000"
}}
{{- if .Values.valkey.enabled }}
{{- $_ := set $env "PAPERLESS_REDIS" (printf "redis://%s:6379" (include "paperless.componentName" (list . "valkey"))) }}
{{- else if .Values.externalValkey.url }}
{{- $_ := set $env "PAPERLESS_REDIS" .Values.externalValkey.url }}
{{- end }}
{{- if .Values.tika.enabled }}
{{- $_ := set $env "PAPERLESS_TIKA_ENABLED" "true" }}
{{- $_ := set $env "PAPERLESS_TIKA_ENDPOINT" (printf "http://%s:80" (include "paperless.componentName" (list . "tika"))) }}
{{- $_ := set $env "PAPERLESS_TIKA_GOTENBERG_ENDPOINT" (printf "http://%s:80" (include "paperless.componentName" (list . "gotenberg"))) }}
{{- end }}
{{- range $key, $value := .Values.paperless.env }}
{{- $_ := set $env $key (toString $value) }}
{{- end }}
{{- toYaml $env }}
{{- end }}

{{/* Whether a paperless.env boolean is true, as paperless parses it: (list $ "PAPERLESS_AI_ENABLED") */}}
{{- define "paperless.envTrue" -}}
{{- $env := include "paperless.env" (index . 0) | fromYaml }}
{{- if has (lower (toString (index $env (index . 1) | default ""))) (list "true" "1" "yes" "y" "t") }}true{{ end }}
{{- end }}

{{/* What every paperless container shares: image, security context, environment */}}
{{- define "paperless.container" -}}
image: {{ include "paperless.image" (list . .Values.image) }}
imagePullPolicy: {{ .Values.image.pullPolicy }}
securityContext:
  {{- toYaml .Values.paperless.securityContext | nindent 2 }}
{{- with .Values.paperless.extraEnv }}
env:
  {{- toYaml . | nindent 2 }}
{{- end }}
envFrom:
  {{- include "paperless.envFrom" . | nindent 2 }}
{{- end }}

{{/* The ConfigMap, then the Secret (which wins on duplicate keys), then extraEnvFrom */}}
{{- define "paperless.envFrom" -}}
- configMapRef: {name: {{ include "paperless.componentName" (list . "env") }}}
{{- with .Values.paperless.existingSecret }}
- secretRef: {name: {{ . }}}
{{- end }}
{{- with .Values.paperless.extraEnvFrom }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
The data volume's folders, as every manage.py command needs them: its paths check writes to consume
too. (list "export" "tessdata") adds the export folder and Tesseract's data
*/}}
{{- define "paperless.dataMounts" -}}
- {name: data, mountPath: /usr/src/paperless/data, subPath: paperless-data}
- {name: data, mountPath: /usr/src/paperless/media, subPath: paperless-media}
- {name: data, mountPath: /usr/src/paperless/consume, subPath: paperless-consume}
{{- if has "export" . }}
- {name: data, mountPath: /usr/src/paperless/export, subPath: paperless-export}
{{- end }}
{{- if has "tessdata" . }}
- {name: tessdata, mountPath: /mnt/tessdata, readOnly: true}
{{- end }}
{{- end }}

{{/* The extra scripts' mounts */}}
{{- define "paperless.scriptMounts" -}}
{{- range $name, $_ := .Values.paperless.scripts }}
- {name: scripts, mountPath: /mnt/scripts/{{ $name }}, subPath: {{ $name }}, readOnly: true}
{{- end }}
{{- end }}

{{/* A component pod's scheduling: nodeSelector, tolerations, affinity */}}
{{- define "paperless.scheduling" -}}
{{- with .nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "paperless.imagePullSecrets" -}}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
