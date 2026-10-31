# charts

Helm charts for my [homelab](https://github.com/sebastka/homelab), published as OCI artifacts on GitHub Container Registry and attested by GitHub Actions.

| Chart | Application |
|-------|-------------|
| [paperless](charts/paperless) | [paperless-ngx](https://github.com/paperless-ngx/paperless-ngx), on [sebastka/containers' image](https://github.com/sebastka/containers/tree/main/apps/paperless) |

```sh
helm install paperless oci://ghcr.io/sebastka/charts/paperless --namespace paperless --create-namespace
gh attestation verify --repo sebastka/charts oci://ghcr.io/sebastka/charts/paperless:<version>
```

With kustomize, as the homelab consumes them:

```yaml
helmCharts:
  - name: paperless
    repo: oci://ghcr.io/sebastka/charts
    version: 0.1.0
    releaseName: paperless
    namespace: paperless
    valuesFile: values.yaml
```

## Conventions

- **Images pinned by digest**, as `tag: <version>@sha256:<digest>` in `values.yaml`: overriding the tag overrides the digest with it. Renovate updates both, the chart's `appVersion` along with its image, and bumps the chart's `version`.
- **Secure by default**: non-root, read-only root filesystem, no capabilities, `RuntimeDefault` seccomp, no ServiceAccount token. Optional resources (Gateway API, Cilium) are off by default.
- **`values.schema.json`** rejects unknown keys: a typo fails the install rather than being ignored.
- **Selectors never change** (`app.kubernetes.io/name` and `instance`): they are immutable.
- Templates are named after what they render (`Deployment.paperless.yaml`), like the homelab's manifests.

## Development

| Check | Command |
|-------|---------|
| YAML | `yamllint --strict .` |
| Lint, with each `ci/*-values.yaml` | `ct lint --config ct.yaml --all` |
| Unit tests ([helm-unittest](https://github.com/helm-unittest/helm-unittest)) | `helm unittest charts/<chart>` |
| Schemas, CRDs included | `helm template x charts/<chart> -f charts/<chart>/tests/values/full.yaml \| kubeconform -strict -summary -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' -` |
| Chart READMEs ([helm-docs](https://github.com/norwoodj/helm-docs), from `README.md.gotmpl` and the `# --` comments in `values.yaml`) | `docker run --rm -v "$PWD:/helm-docs" -w /helm-docs jnorwood/helm-docs:v1.14.2 --chart-search-root charts` |

CI runs them all, then installs every changed chart on kind (`ct install`, once per `ci/*-values.yaml`). Every change to a chart must bump its `version`. A version that is not on the registry yet is released on merge to `master`.
