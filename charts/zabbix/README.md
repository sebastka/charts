# zabbix

Zabbix server and frontend, one process per container, against an external PostgreSQL

<!-- Nothing Renovate updates (chart and app versions, image tags) appears here: its pull requests cannot regenerate this README, and CI fails on a stale one. -->

Zabbix server and the web frontend, each process in its own container, on [sebastka/containers' images](https://github.com/sebastka/containers/tree/main/apps): built on Docker Hardened Images, with no shell in the frontend pair and no entrypoint scripts anywhere. Upstream's images run php-fpm and nginx together under supervisord and render their configuration from `ZBX_*` environment variables at start-up; this chart renders it instead, so what the server reads is in `helm get manifest` rather than assembled inside the container.

## Installing

```sh
helm install zabbix oci://ghcr.io/sebastka/charts/zabbix --namespace monitoring --create-namespace \
  --set database.host=postgres.example.com --set database.existingSecret=zabbix-database
```

`database.host` is required: **this chart deploys no PostgreSQL**. Zabbix keeps years of history, which belongs on a database you back up and upgrade deliberately, not on one that disappears with `helm uninstall`. Point it at a server with an empty database and a role that owns it; the chart loads the schema into it.

Releases are attested by GitHub Actions:

```sh
gh attestation verify --repo sebastka/charts oci://ghcr.io/sebastka/charts/zabbix:<version>
```

## What it deploys

| Object | Notes |
|--------|-------|
| `zabbix-server` Deployment | One replica, `Recreate`: two servers writing to one database corrupt it, so never two at once, not even briefly during a rollout |
| `zabbix-web` Deployment | nginx and php-fpm in one pod. nginx reaches php-fpm over the pod's loopback, so the FastCGI port is on no Service and no network policy has to account for it |
| Two Services | The frontend on `service.web`, and the server on `service.server` for agents and proxies to connect to |
| HTTPRoute | `httpRoute.enabled`, Gateway API, named after the release for policies to target |

## The database

The password reaches each pod as a file from a Secret, never as an environment variable:

```yaml
database:
  host: postgres.example.com
  existingSecret: zabbix-database   # or database.password, which makes the chart create one
  existingSecretKey: postgres-password
```

The frontend reads that file directly. The server cannot: `zabbix_server` takes `DBPassword` from its configuration file and from nowhere else — there is no `DBPasswordFile`, only Vault — so an init container appends the line to a copy of the ConfigMap's file on a `medium: Memory` volume. The password therefore stays out of the ConfigMap, out of `helm get manifest` and off every node's disk.

### The schema

`database.createSchema` (on by default) loads `schema.sql`, `images.sql` and `data.sql` from an init container before the server starts. It waits for the database to answer, then checks for `public.users` and does nothing when a schema is already there, so it is a single query on every start after the first. It is an init container rather than a Helm hook deliberately: a hook runs before the rest of the release and fails the install outright when the database is not reachable yet, where this simply waits.

It uses the server image's own `psql` — the same image that carries the `.sql` files — so no second image is pulled and no second registry has to be reachable.

Turn it off when the database is managed elsewhere. Zabbix upgrades its own schema on start-up; this only ever populates an empty database.

## Configuration

`server.config` is rendered into `zabbix_server.conf`, one `Key=Value` per line, and Zabbix's own defaults apply to anything left out. `server.extraConfig` is appended verbatim for what the values do not name:

```yaml
server:
  config:
    StartPollers: 10
    CacheSize: 128M
  extraConfig: |
    HANodeName=first
    NodeAddress=zabbix-server:10051
```

Both roll the pod when they change, through a checksum annotation.

The frontend takes `web.timezone` for PHP and `web.extraConfig` for anything else `zabbix.conf.php` can hold, such as `$ZBX_SERVER_NAME`.

## What this chart leaves to you

**Agents.** Nothing here deploys `zabbix-agent` or `zabbix-agent2`. The server monitors what it can reach; run agents as their own DaemonSet or Deployment.

**Network policies.** Paperless's chart ships CiliumNetworkPolicies; this one does not, because the traffic that matters here is site-specific — agents and proxies connect to `10051` from wherever they happen to run, and the server polls SNMP, ICMP and HTTP targets across the network. A policy written from this chart's point of view would be either useless or wrong. Put yours in `extraObjects`, where they are templated with the release.

**ICMP checks.** `icmpping` items shell out to `fping`, which needs the pod's group inside `net.ipv4.ping_group_range`. The server's pod sets that sysctl itself, but the kubelet has to allow it: `--allowed-unsafe-sysctls=net.ipv4.ping_group_range`, or the pod will not start.

## Upgrading

The Deployments' selectors are `app.kubernetes.io/name` and `app.kubernetes.io/instance`: immutable, so never renamed. Nothing in this chart holds state — the database does.

## Requirements

Kubernetes: `>=1.30.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| commonLabels | object | `{}` | Labels added to every object |
| database.createSchema | bool | `true` | Load schema.sql, images.sql and data.sql into an empty database before the server starts. An init container on the server pod, using the psql and the .sql files in the server image: it waits for the database, and does nothing when a schema is already there. |
| database.existingSecret | string | `""` | Secret holding the password, instead of spelling it out above |
| database.existingSecretKey | string | `"password"` | Key within that Secret |
| database.host | string | `""` | Hostname of the PostgreSQL server. Required. |
| database.name | string | `"zabbix"` | Database name |
| database.password | string | `""` | Password. Ignored when existingSecret is set. |
| database.port | int | `5432` | Port |
| database.user | string | `"zabbix"` | Role the server and the frontend connect as |
| extraObjects | list | `[]` | Objects rendered as they are, for anything this chart does not cover |
| fullnameOverride | string | `""` | Override the fully qualified name |
| httpRoute.annotations | object | `{}` |  |
| httpRoute.enabled | bool | `false` | Expose the frontend through a Gateway API HTTPRoute |
| httpRoute.hostnames | list | `[]` |  |
| httpRoute.parentRefs | list | `[]` |  |
| imagePullSecrets | list | `[]` | Image pull secrets for every pod |
| nameOverride | string | `""` | Override the chart name |
| server.affinity | object | `{}` |  |
| server.config | object | `{"CacheSize":"32M","HistoryCacheSize":"16M","LogType":"console","StartDiscoverers":5,"StartHTTPPollers":1,"StartPingers":1,"StartPollers":5,"Timeout":4,"ValueCacheSize":"32M"}` | Settings rendered into zabbix_server.conf. Zabbix's own defaults apply to anything omitted. |
| server.extraConfig | string | `""` | Extra lines appended to zabbix_server.conf, for anything this chart does not expose |
| server.image.pullPolicy | string | `"IfNotPresent"` |  |
| server.image.repository | string | `"ghcr.io/sebastka/zabbix-server"` |  |
| server.image.tag | string | pinned in values.yaml, updated by Renovate | Tag, optionally with its digest (`tag@sha256:…`). Defaults to the chart's appVersion |
| server.nodeSelector | object | `{}` |  |
| server.podAnnotations | object | `{}` |  |
| server.podLabels | object | `{}` |  |
| server.podSecurityContext.fsGroup | int | `1995` |  |
| server.podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` |  |
| server.podSecurityContext.runAsGroup | int | `1995` |  |
| server.podSecurityContext.runAsNonRoot | bool | `true` |  |
| server.podSecurityContext.runAsUser | int | `1997` |  |
| server.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| server.podSecurityContext.sysctls[0].name | string | `"net.ipv4.ping_group_range"` |  |
| server.podSecurityContext.sysctls[0].value | string | `"0 1995"` |  |
| server.resources.limits.memory | string | `"1Gi"` |  |
| server.resources.requests.memory | string | `"256Mi"` |  |
| server.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| server.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| server.securityContext.readOnlyRootFilesystem | bool | `true` |  |
| server.tolerations | list | `[]` |  |
| service.annotations | object | `{}` |  |
| service.server | int | `10051` | Port the server listens on for agents and proxies |
| service.web | int | `80` | Port the frontend is served on |
| web.affinity | object | `{}` |  |
| web.extraConfig | string | `""` | Extra PHP statements appended to zabbix.conf.php |
| web.nginx.image.pullPolicy | string | `"IfNotPresent"` |  |
| web.nginx.image.repository | string | `"ghcr.io/sebastka/zabbix-web-nginx"` |  |
| web.nginx.image.tag | string | pinned in values.yaml, updated by Renovate | Tag and digest. Same Zabbix version as the server: Renovate updates the three together |
| web.nginx.resources.limits.memory | string | `"128Mi"` |  |
| web.nginx.resources.requests.memory | string | `"32Mi"` |  |
| web.nginx.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":65532,"runAsUser":65532}` | The nginx image's own user. /var/lib/nginx is 0750 and owned by it, so another uid cannot even traverse in: this is not the same user as php below, which is why neither is set on the pod. |
| web.nodeSelector | object | `{}` |  |
| web.php.image.pullPolicy | string | `"IfNotPresent"` |  |
| web.php.image.repository | string | `"ghcr.io/sebastka/zabbix-web-php"` |  |
| web.php.image.tag | string | pinned in values.yaml, updated by Renovate | Tag and digest. Same Zabbix version as the server: Renovate updates the three together |
| web.php.resources.limits.memory | string | `"512Mi"` |  |
| web.php.resources.requests.memory | string | `"128Mi"` |  |
| web.php.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":1995,"runAsUser":1997}` | Zabbix's own uid and gid, as in the server image |
| web.podAnnotations | object | `{}` |  |
| web.podLabels | object | `{}` |  |
| web.podSecurityContext | object | `{"fsGroup":1995,"fsGroupChangePolicy":"OnRootMismatch","runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}` | No runAsUser here: the two containers run as different users, and each sets its own. fsGroup is what lets both write the shared emptyDirs. |
| web.replicas | int | `1` |  |
| web.timezone | string | `"UTC"` | PHP timezone for the frontend |
| web.tolerations | list | `[]` |  |
