# Radarr Helm Chart

This chart deploys Radarr using the shared dependency `lib-chart` (`0.0.7`).

## Installation

```bash
helm install radarr . --namespace media-center
```

## Dependencies

- `lib-chart` (`0.0.7`) from `oci://ghcr.io/orhayoun-eevee`

Update dependencies from chart root:

```bash
helm dependency build
```

## Validation and Testing

This chart follows the same reusable 5-layer validation pipeline used by `helm-common-lib`:

1. Syntax and structure (`yamllint`, `helm lint --strict`)
2. Kubernetes schema validation (`kubeconform`) on rendered scenarios
3. Metadata and version checks (`ct lint` + version bump policy)
4. Unit and regression checks (`helm-unittest` + scenario snapshots)
5. Policy checks (`checkov`, `kube-linter`)

### CI Workflows

- PR validation: `.github/workflows/on-pr.yaml` -> `build-workflow/.github/workflows/helm-validate.yaml`
- Release: `.github/workflows/on-tag.yaml` -> `build-workflow/.github/workflows/release-chart.yaml`

### Local Docker Validation

```bash
make docker-build
make deps
make snapshot-update
make ci
```

### Snapshot Drift Behavior

Snapshots in `tests/snapshots/*.yaml` are part of CI contract.
If rendered output changes and snapshots are not updated (or are updated incorrectly), Layer 4 fails the PR.

Schema-negative fixtures in `tests/schema-fail-cases/*.yaml` are also validated in Layer 4 and must fail schema validation for the expected reason.

### Test Assets

- `tests/radarr_contract_test.yaml`
- `tests/scenarios/full.yaml`
- `tests/scenarios/minimal.yaml`
- `tests/snapshots/*.yaml`

## Version Bump Automation

```bash
make bump VERSION=x.y.z
```

This updates `Chart.yaml`, refreshes `Chart.lock`, and regenerates snapshots.

## App-Specific Notes

- Namespace: `media-center`
- Main container runs as UID/GID `1013/1011`
- Config PVC claim: `radarr-config` (RWO)

## References

- https://radarr.video/
- `Chart.yaml`
- `values.yaml`

## Dependency Automation Policy

This repo uses Renovate scoped automerge for low-risk updates only:

- `github-actions`: `digest`, `pin`, `pinDigest`, `patch`, `minor`
- `helmv3` dependencies: `digest`, `pin`, `pinDigest`, `patch`, `minor`
- container image updates (`custom.regex` in `values.yaml`): `digest`, `pin`, `pinDigest`, `patch`, `minor`
- `major` updates are not automerged

Branch protection on `main` is expected to require passing validation checks before merge.

For Renovate PRs that change `values.yaml`, `.github/workflows/renovate-snapshot-update.yaml` runs `make snapshot-update` and commits updated `tests/snapshots/*` back to the PR branch so strict snapshot checks remain enforced.
