{{/* Chart name */}}
{{- define "zabbix.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Full name: the release name alone when it already contains the chart name */}}
{{- define "zabbix.fullname" -}}
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

{{/* Name of a component's resources: (list $ "web") */}}
{{- define "zabbix.componentName" -}}
{{- $ctx := index . 0 }}
{{- printf "%s-%s" (include "zabbix.fullname" $ctx | trunc 56 | trimSuffix "-") (index . 1) }}
{{- end }}

{{/* Component metadata */}}
{{- define "zabbix.components" -}}
server: {name: zabbix-server, component: monitoring-server}
web: {name: zabbix-web, component: monitoring-frontend}
{{- end }}

{{/* Selector labels: (list $ "web"). Selectors are immutable: never add to them */}}
{{- define "zabbix.selectorLabels" -}}
{{- $ctx := index . 0 }}
{{- $component := index (include "zabbix.components" $ctx | fromYaml) (index . 1) -}}
app.kubernetes.io/name: {{ $component.name }}
app.kubernetes.io/instance: {{ $ctx.Release.Name }}
{{- end }}

{{/* Labels */}}
{{- define "zabbix.labels" -}}
{{- $ctx := index . 0 }}
{{- $component := index (include "zabbix.components" $ctx | fromYaml) (index . 1) -}}
{{ include "zabbix.selectorLabels" . }}
app.kubernetes.io/component: {{ $component.component }}
app.kubernetes.io/part-of: {{ include "zabbix.name" $ctx }}
app.kubernetes.io/version: {{ $ctx.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ $ctx.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" $ctx.Chart.Name $ctx.Chart.Version | replace "+" "_" }}
{{- with $ctx.Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Pod template labels: (list $ "web"). Without helm.sh/chart and app.kubernetes.io/version, which
would restart every pod on every chart release, an image bump of the other component included
*/}}
{{- define "zabbix.podLabels" -}}
{{- $ctx := index . 0 }}
{{- $component := index (include "zabbix.components" $ctx | fromYaml) (index . 1) -}}
{{ include "zabbix.selectorLabels" . }}
app.kubernetes.io/component: {{ $component.component }}
app.kubernetes.io/part-of: {{ include "zabbix.name" $ctx }}
{{- with $ctx.Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* Image reference: (list $image .Chart.AppVersion). The tag may carry a digest (tag@sha256:...) */}}
{{- define "zabbix.image" -}}
{{- $image := index . 0 }}
{{- printf "%s:%s" $image.repository (default (index . 1) $image.tag) }}
{{- end }}

{{/* Restart a component's pods when its own configuration changes: (list $ "web") */}}
{{- define "zabbix.configChecksum" -}}
{{- $ctx := index . 0 }}
checksum/config: {{ include (printf "zabbix.%sConfigData" (index . 1)) $ctx | sha256sum }}
{{- end }}

{{/* Fail early on a combination that cannot work, rather than at run time */}}
{{- define "zabbix.validate" -}}
{{- if not .Values.database.host }}
{{- fail "database.host is required: this chart does not deploy PostgreSQL" }}
{{- end }}
{{- if and (not .Values.database.existingSecret) (not .Values.database.password) }}
{{- fail "set database.password, or database.existingSecret to take it from a Secret" }}
{{- end }}
{{- end }}
