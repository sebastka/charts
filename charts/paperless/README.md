# paperless

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.3.1](https://img.shields.io/badge/AppVersion-3.3.1-informational?style=flat-square)

paperless-ngx, rootless and one process per container, with optional Tika, Gotenberg and Valkey

[paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) without s6: one pod, one process per
container (webserver, consumer, Celery worker and scheduler), every container rootless with a read-only
root filesystem. Its init containers mirror the s6 init chain of upstream's image: Tesseract data, waits
for the database and the broker, folders, migrations, index, superuser, system checks.

It runs [sebastka/containers' image](https://github.com/sebastka/containers/tree/main/apps/paperless),
built on Docker Hardened Images, without a shell: upstream's image will not work.

## Installing

```sh
helm install paperless oci://ghcr.io/sebastka/charts/paperless --namespace paperless --create-namespace
```

With nothing else set, paperless runs on SQLite with the bundled Valkey, Tika and Gotenberg. Set
`paperless.existingSecret` to a Secret holding at least `PAPERLESS_SECRET_KEY`, and, for PostgreSQL,
`PAPERLESS_DBHOST` (in `paperless.env`) and `PAPERLESS_DBPASS` (in the Secret).

Releases are attested by GitHub Actions:

```sh
gh attestation verify --repo sebastka/charts oci://ghcr.io/sebastka/charts/paperless:0.1.0
```

## Components

| Component | Enabled by | Notes |
|-----------|------------|-------|
| Valkey | `valkey.enabled` (opt-out) | The Celery broker, without persistence. Disable it for `externalValkey.url`, or `PAPERLESS_REDIS` in the Secret |
| Tika and Gotenberg | `tika.enabled`, `gotenberg.enabled` (opt-out) | Office documents and emails. Together, or not at all |
| HTTPRoute | `httpRoute.enabled` | Gateway API, named after the release for policies to target. `httpRoute.extraRules` takes implementation-specific filters |
| CiliumNetworkPolicies | `ciliumNetworkPolicy.enabled` | Paperless reaches its components, and only paperless reaches them. Add the database, mail servers… to `ciliumNetworkPolicy.egress` |

## Configuration

`paperless.env` is rendered into a ConfigMap, over what the chart sets itself: the folders it mounts,
`PAPERLESS_REDIS` and the Tika and Gotenberg endpoints (from the enabled components), `TESSDATA_PREFIX`,
and the listening address. Changing it rolls the pod. Secrets go in `paperless.existingSecret`, which
takes precedence.

```yaml
paperless:
  existingSecret: paperless-secrets  # PAPERLESS_SECRET_KEY, PAPERLESS_DBPASS…
  env:
    PAPERLESS_URL: https://paperless.example.com
    PAPERLESS_DBHOST: postgres.example.com
    PAPERLESS_OCR_LANGUAGES: deu fra  # Downloaded by the tessdata init container
    PAPERLESS_OCR_LANGUAGE: deu+fra
    PAPERLESS_TIME_ZONE: Europe/Berlin
```

The webserver runs with the chart's Django settings (`paperless.webserver.customSettings`): `__Host-`
prefixed, Secure cookies, so serve it over HTTPS, or turn them off.

## Password logins behind SSO

`PAPERLESS_DISABLE_REGULAR_LOGIN` hides the login form, but leaves three password logins open:

- HTTP Basic authentication on the API: the chart's webserver settings drop it when the variable is set.
- `POST /api/token/`, which mints an API token from a username and a password.
- `/admin/login/`, Django's admin login form.

The last two are the gateway's to block, for instance with `httpRoute.extraRules` matching them and an
implementation-specific filter answering 403.

## Upgrading

The Deployment's selector is `app.kubernetes.io/name` and `app.kubernetes.io/instance`: immutable, so
never renamed. The PersistentVolumeClaim the chart creates is kept on uninstall.

## Requirements

Kubernetes: `>=1.30.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ciliumNetworkPolicy.egress | list | `[]` | Extra egress rules of paperless (the database, mail servers, LLM…) |
| ciliumNetworkPolicy.enabled | bool | `false` | CiliumNetworkPolicies: paperless's ingress (`ingress`) and egress (its components, raw.githubusercontent.com when `PAPERLESS_OCR_LANGUAGES` is set, `egress`), and the components' ingress, from paperless only. FQDN rules need a DNS proxy rule, such as a cluster-wide policy for kube-dns |
| ciliumNetworkPolicy.ingress | list | `[]` | Ingress rules of paperless (the gateway…) |
| commonLabels | object | `{}` | Labels added to every resource |
| externalValkey.url | string | `""` | Broker URL (`PAPERLESS_REDIS`) when `valkey.enabled` is false. With credentials in it, leave this empty and set `PAPERLESS_REDIS` in `paperless.existingSecret` instead |
| extraObjects | list | `[]` | Extra manifests to deploy with the release. Strings and objects alike are rendered with `tpl` |
| fullnameOverride | string | `""` | Overrides the full name of the resources (default: `<release>-paperless`, or `<release>` when it contains the chart name) |
| gotenberg.affinity | object | `{}` |  |
| gotenberg.args | list | `["gotenberg","--chromium-disable-javascript=true","--chromium-allow-list=file:///tmp/.*"]` | Gotenberg's arguments: no JavaScript, and no file access outside its temporary folder |
| gotenberg.enabled | bool | `true` | Deploy Gotenberg and set paperless's Gotenberg endpoint |
| gotenberg.image.pullPolicy | string | `"IfNotPresent"` |  |
| gotenberg.image.repository | string | `"docker.io/gotenberg/gotenberg"` |  |
| gotenberg.image.tag | string | `"8.37@sha256:f29984bd1e226bf1b93ba90af06000afa8b315853e99d27b9aaa41b93f15c769"` |  |
| gotenberg.nodeSelector | object | `{}` |  |
| gotenberg.podAnnotations | object | `{}` |  |
| gotenberg.podLabels | object | `{}` |  |
| gotenberg.podSecurityContext.fsGroup | int | `1000` |  |
| gotenberg.podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` |  |
| gotenberg.podSecurityContext.runAsGroup | int | `1000` |  |
| gotenberg.podSecurityContext.runAsNonRoot | bool | `true` |  |
| gotenberg.podSecurityContext.runAsUser | int | `1000` |  |
| gotenberg.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| gotenberg.resources.limits.memory | string | `"128Mi"` |  |
| gotenberg.resources.requests.memory | string | `"64Mi"` |  |
| gotenberg.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| gotenberg.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| gotenberg.securityContext.readOnlyRootFilesystem | bool | `true` |  |
| gotenberg.tolerations | list | `[]` |  |
| httpRoute.annotations | object | `{}` |  |
| httpRoute.enabled | bool | `false` | Expose paperless through an HTTPRoute |
| httpRoute.extraRules | list | `[]` | Extra rules, besides the catch-all one: a longer path prefix takes precedence regardless of order. Implementation-specific filters (Envoy Gateway's HTTPRouteFilter…) go here. The HTTPRoute is named after the full name, for policies to target it |
| httpRoute.filters | list | `[]` | Filters of the rule sending traffic to paperless (security headers…) |
| httpRoute.hostnames | list | `[]` |  |
| httpRoute.labels | object | `{}` |  |
| httpRoute.parentRefs | list | `[]` | Gateways to attach to |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"ghcr.io/sebastka/paperless"` | paperless image. The chart runs the commands of [sebastka/containers' image](https://github.com/sebastka/containers/tree/main/apps/paperless) (no shell, no s6: `paperless-tessdata`, `paperless-wait-for-db`), not upstream's |
| image.tag | string | `"3.3.1@sha256:dc45fea63b05f0439a650a4c1b23a1b499ef9d11d4deaa41f36ae783edc472d6"` | Tag, optionally with its digest (`tag@sha256:…`). Defaults to the chart's appVersion |
| imagePullSecrets | list | `[]` | Secrets to pull every image with |
| nameOverride | string | `""` | Overrides the chart name, used in resource names |
| paperless.affinity | object | `{}` |  |
| paperless.aiReviewScript | bool | `true` | Install `paperless-ai-review` in the worker container: an interactive review of the AI suggestions over the existing library (`kubectl exec -it … -c worker -- paperless-ai-review --help`) |
| paperless.annotations | object | `{}` | Annotations of the Deployment |
| paperless.containers.consumer | object | `{"resources":{"limits":{"memory":"512Mi"},"requests":{"memory":"128Mi"}}}` | `manage.py document_consumer`, watching the consume folder |
| paperless.containers.scheduler | object | `{"resources":{"limits":{"memory":"512Mi"},"requests":{"memory":"256Mi"}}}` | Celery beat |
| paperless.containers.webserver | object | `{"resources":{"limits":{"memory":"768Mi"},"requests":{"memory":"384Mi"}}}` | granian, serving the web UI and the API on port 8000 |
| paperless.containers.worker | object | `{"resources":{"limits":{"memory":"4096Mi"},"requests":{"memory":"256Mi"}}}` | Celery worker: OCR, classification, AI |
| paperless.env | object | `{}`, besides what the chart sets | paperless configuration (https://docs.paperless-ngx.com/configuration/), rendered into a ConfigMap. Merged over what the chart sets itself: the paths it mounts, the Valkey, Tika and Gotenberg endpoints, `TESSDATA_PREFIX` and the listening address. Values are rendered as strings |
| paperless.existingSecret | string | `""` | Secret with the sensitive part of the configuration, as environment variables (`PAPERLESS_SECRET_KEY`, `PAPERLESS_DBPASS`…). Takes precedence over `paperless.env` |
| paperless.extraEnv | list | `[]` | Extra environment variables for every paperless container (`valueFrom` allowed) |
| paperless.extraEnvFrom | list | `[]` | Extra `envFrom` sources for every paperless container, after the ConfigMap and the Secret |
| paperless.initContainers.folders | object | `{"resources":{"limits":{"memory":"64Mi"},"requests":{"memory":"64Mi"}}}` | Creates the data, media, consume and export folders |
| paperless.initContainers.llmindexMigrate | object | `{"resources":{"limits":{"memory":"256Mi"},"requests":{"memory":"128Mi"}}}` | `manage.py document_llmindex migrate`, only when `PAPERLESS_AI_ENABLED` is true |
| paperless.initContainers.migrate | object | `{"resources":{"limits":{"memory":"384Mi"},"requests":{"memory":"256Mi"}}}` | `manage.py migrate` |
| paperless.initContainers.reindex.enabled | bool | `true` |  |
| paperless.initContainers.reindex.resources.limits.memory | string | `"512Mi"` |  |
| paperless.initContainers.reindex.resources.requests.memory | string | `"256Mi"` |  |
| paperless.initContainers.superuser | object | `{"enabled":true,"resources":{"limits":{"memory":"384Mi"},"requests":{"memory":"128Mi"}}}` | `manage.py manage_superuser`, from `PAPERLESS_ADMIN_USER` and `PAPERLESS_ADMIN_PASSWORD` |
| paperless.initContainers.systemChecks | object | `{"enabled":true,"resources":{"limits":{"memory":"256Mi"},"requests":{"memory":"256Mi"}}}` | `manage.py check` |
| paperless.initContainers.tessdata | object | `{"resources":{"limits":{"memory":"64Mi"},"requests":{"memory":"64Mi"}}}` | Copies the image's Tesseract data, and downloads `PAPERLESS_OCR_LANGUAGES`, into `TESSDATA_PREFIX` |
| paperless.initContainers.waitForDb | object | `{"resources":{"limits":{"memory":"128Mi"},"requests":{"memory":"128Mi"}}}` | Waits for PostgreSQL (does nothing on SQLite) |
| paperless.initContainers.waitForRedis | object | `{"resources":{"limits":{"memory":"128Mi"},"requests":{"memory":"128Mi"}}}` | Waits for the broker |
| paperless.nodeSelector | object | `{}` |  |
| paperless.podAnnotations | object | `{}` | Annotations of the pod |
| paperless.podLabels | object | `{}` | Labels of the pod |
| paperless.podSecurityContext.fsGroup | int | `1000` |  |
| paperless.podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` |  |
| paperless.podSecurityContext.runAsGroup | int | `1000` |  |
| paperless.podSecurityContext.runAsNonRoot | bool | `true` |  |
| paperless.podSecurityContext.runAsUser | int | `1000` |  |
| paperless.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| paperless.priorityClassName | string | `""` |  |
| paperless.scripts | object | `{}` | Extra scripts, `name: content`, mounted executable at `/mnt/scripts/<name>` in the consumer and worker containers. Point `PAPERLESS_PRE_CONSUME_SCRIPT` or `PAPERLESS_POST_CONSUME_SCRIPT` at them. The image has no shell: use `#!/opt/paperless/bin/python` |
| paperless.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}` | Security context of every paperless container, init containers included |
| paperless.serviceAccount.annotations | object | `{}` |  |
| paperless.serviceAccount.create | bool | `true` | Create the ServiceAccount |
| paperless.serviceAccount.name | string | `""` | Its name (default: the full name) |
| paperless.terminationGracePeriodSeconds | int | `60` |  |
| paperless.tessdataSizeLimit | string | `"256Mi"` | Size limit of the emptyDir holding Tesseract's data (the image's, plus `PAPERLESS_OCR_LANGUAGES`) |
| paperless.tolerations | list | `[]` |  |
| paperless.webserver.customSettings | bool | `true` | Run the webserver with the chart's Django settings (`files/settings/webserver.py`): an access log in the combined format, `__Host-` prefixed, Secure and SameSite=Strict cookies (HTTPS only), and no HTTP Basic authentication on the API when `PAPERLESS_DISABLE_REGULAR_LOGIN` is set |
| persistence.accessModes[0] | string | `"ReadWriteOnce"` |  |
| persistence.annotations | object | `{}` | Annotations of the PersistentVolumeClaim. It is kept on uninstall (`helm.sh/resource-policy: keep`) |
| persistence.enabled | bool | `true` | Persist paperless's data, media, consume and export folders (as subPaths of one volume). When false, an emptyDir: everything is lost with the pod |
| persistence.existingClaim | string | `""` | Use an existing PersistentVolumeClaim instead of creating one |
| persistence.labels | object | `{}` |  |
| persistence.size | string | `"20Gi"` |  |
| persistence.storageClassName | string | `""` |  |
| persistence.volumeName | string | `""` | Bind to a specific PersistentVolume |
| service.annotations | object | `{}` |  |
| service.port | int | `80` |  |
| service.type | string | `"ClusterIP"` |  |
| tika.affinity | object | `{}` |  |
| tika.enabled | bool | `true` | Deploy Apache Tika and set paperless's Tika endpoint |
| tika.image.pullPolicy | string | `"IfNotPresent"` |  |
| tika.image.repository | string | `"docker.io/apache/tika"` |  |
| tika.image.tag | string | `"3.3.1.0-full@sha256:d8e6ed96260ad89307a93195a1b856102987a818ac648502f8efbaf313d32470"` |  |
| tika.nodeSelector | object | `{}` |  |
| tika.podAnnotations | object | `{}` |  |
| tika.podLabels | object | `{}` |  |
| tika.podSecurityContext.fsGroup | int | `35002` |  |
| tika.podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` |  |
| tika.podSecurityContext.runAsGroup | int | `35002` |  |
| tika.podSecurityContext.runAsNonRoot | bool | `true` |  |
| tika.podSecurityContext.runAsUser | int | `35002` |  |
| tika.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| tika.resources.limits.memory | string | `"512Mi"` |  |
| tika.resources.requests.memory | string | `"256Mi"` |  |
| tika.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| tika.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| tika.securityContext.readOnlyRootFilesystem | bool | `true` |  |
| tika.tolerations | list | `[]` |  |
| valkey.affinity | object | `{}` |  |
| valkey.args | list | `["--save","","--protected-mode","no"]` | Valkey's arguments: no persistence (the broker only holds tasks in flight) |
| valkey.enabled | bool | `true` | Deploy Valkey as paperless's broker. Disable to use `externalValkey` |
| valkey.image.pullPolicy | string | `"IfNotPresent"` |  |
| valkey.image.repository | string | `"docker.io/valkey/valkey"` |  |
| valkey.image.tag | string | `"9.1.2-alpine@sha256:48332870af354a799964c0012ae1194a0bf2bf894eb508f945810596dc2d8d11"` |  |
| valkey.nodeSelector | object | `{}` |  |
| valkey.podAnnotations | object | `{}` |  |
| valkey.podLabels | object | `{}` |  |
| valkey.podSecurityContext.fsGroup | int | `1000` |  |
| valkey.podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` |  |
| valkey.podSecurityContext.runAsGroup | int | `1000` |  |
| valkey.podSecurityContext.runAsNonRoot | bool | `true` |  |
| valkey.podSecurityContext.runAsUser | int | `999` |  |
| valkey.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| valkey.resources.limits.memory | string | `"64Mi"` |  |
| valkey.resources.requests.memory | string | `"64Mi"` |  |
| valkey.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| valkey.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| valkey.securityContext.readOnlyRootFilesystem | bool | `true` |  |
| valkey.tolerations | list | `[]` |  |
