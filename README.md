# Radarr Helm Chart
 
This Helm chart deploys Radarr, a movie collection manager, using the `app-chart` dependency pattern. The chart orchestrates application deployment, networking, and monitoring resources.

## Installation

```bash
helm install radarr ./charts/services/radarr --namespace media-center
```

## Configuration

See `values.yaml` for all available configuration options. The chart is organized into main sections:

- `app-chart`: Core application deployment configuration (Deployment, Services, PVC, etc.)
- `network`: Network access and security policies (HTTPRoute, NetworkPolicy)
- `metrics`: Monitoring, alerting, and dashboards (ServiceMonitor, PrometheusRule)

## Dependencies

This chart depends on:
- `app-chart` (v1.0.0) - Common application chart library

Before installing, ensure the dependency is available.

Update dependencies:
```bash
cd charts/services/radarr
helm dependency update
```

## Architecture and Operational Considerations

### Single Replica Deployment

This chart deploys **exactly 1 replica** of Radarr. This is an intentional architectural decision, not a limitation.

**Rationale:**
- The PersistentVolumeClaim (PVC) uses `ReadWriteOnce` access mode
- A `ReadWriteOnce` PVC can only be attached to a single pod at a time
- Radarr does not support multiple instances writing to the same configuration directory
- Running multiple replicas would require shared storage (ReadWriteMany) and application-level coordination, which Radarr does not support

**Implications:**
- No horizontal scaling is possible
- High availability must be achieved through other means (backups, restore procedures)
- Pod failures result in service unavailability until the pod is restarted

### Deployment Strategy: Recreate

The deployment uses `strategy.type: Recreate` instead of the default `RollingUpdate`.

**Rationale:**
- Required due to PVC attach limits: a single PVC cannot be attached to multiple pods simultaneously
- Rolling updates would require the new pod to attach the PVC while the old pod still has it attached, which is not possible with `ReadWriteOnce`

**Behavior:**
- During upgrades, the old pod is **terminated first** before the new pod starts
- This results in **downtime during deployments**
- Downtime is **accepted and expected** for this service

**Downtime Characteristics:**
- Typical upgrade downtime: 30-60 seconds (depending on pod termination and startup times)
- Health probes (`startupProbe`, `readinessProbe`, `livenessProbe`) are configured to ensure clean startup
- `terminationGracePeriodSeconds: 60` allows graceful shutdown

### PodDisruptionBudget Behavior

The chart configures a PodDisruptionBudget (PDB) with `minAvailable: 1` when `replicas: 1`.

**Configuration:**
- `minAvailable: 1` - Ensures at least one pod is always available
- `unhealthyPodEvictionPolicy: AlwaysAllow` - Allows eviction of unhealthy pods during node drains

**Behavior:**
- With 1 replica and `minAvailable: 1`, **zero voluntary evictions** are allowed for **healthy** pods
- `kubectl drain` operations will **hang waiting** for a healthy pod to be evicted
- **Unhealthy pods can be evicted** even during node drains, preventing deadlock when the pod is already broken
- This prevents accidental service disruption during node maintenance while improving maintenance behavior

**Operational Implications:**
- Healthy pods are protected from eviction during node drains
- Unhealthy pods can be evicted, allowing node maintenance to proceed even when the pod is broken
- For node drains with healthy pods, operators must either:
  1. Temporarily delete the PDB before draining
  2. Manually delete the pod before draining the node
  3. Accept that drains will hang until manual intervention

**Note:** The `unhealthyPodEvictionPolicy: AlwaysAllow` setting improves operational flexibility by allowing eviction of broken pods while maintaining the "1 replica must stay up" protection for healthy pods.

### PVC Lifecycle Management

The PersistentVolumeClaim for Radarr configuration is configured with `retain: true`.

**Configuration:**
- PVC name: `radarr-config`
- Storage class: `longhorn`
- Size: `1Gi`
- Access mode: `ReadWriteOnce`
- Retention: `retain: true` (PVC is not deleted by Helm)

**Rationale:**
- The PVC contains Radarr's configuration data (database, settings, metadata)
- Configuration data must be preserved across Helm operations
- Accidental deletion would result in data loss

**Helm Behavior:**
- When `retain: true` is set, Helm adds the `helm.sh/resource-policy: keep` annotation to the PVC
- This annotation tells Helm to **not delete** the PVC during:
  - `helm uninstall`
  - `helm upgrade` (with certain rollback scenarios)
  - Chart version changes
- The PVC becomes **orphaned from Helm management** after installation
- Helm will stop managing the PVC lifecycle (updates/deletes)

**Operational Notes:**
- The PVC must be manually deleted if removal is truly desired
- Upgrades should not modify PVC specifications (Helm cannot reconcile changes to kept resources)
- For migrations, ensure PVC compatibility with new chart versions

### Backup and Restore Strategy

Radarr configuration is backed up daily to external NFS storage.

**Backup Configuration:**
- **Backup location**: `/mnt/vol1/media-center/backup/radarr` (NFS mount)
- **Backup frequency**: Daily (automated)
- **Backup content**: Radarr configuration directory (`/config` in the pod)

**Restore Capability:**
- Configuration can be restored at any time from the backup location
- Restore procedures should be documented in operational runbooks
- Backups provide protection against:
  - Accidental configuration changes
  - PVC corruption or loss
  - Data migration needs

**Operational Assurance:**
- Daily backups ensure minimal data loss window (24 hours maximum)
- NFS backup location is separate from the PVC, providing redundancy
- Restore procedures should be tested periodically

## Environment Variables

Radarr supports environment variables to override configuration entries. The chart uses Kubernetes-native `securityContext` for user/group management.

### Currently Configured

- `RADARR__SERVER__PORT: "8080"` - Overrides default port 7878
- `RADARR__SERVER__BINDADDRESS: "0.0.0.0"` - Explicitly bind to all interfaces
- `TZ: "UTC"` - Timezone setting

### Adding Additional Environment Variables

To add additional Radarr-supported environment variables, edit `values.yaml` under `app-chart.deployment.containers.radarr.env`.

**Reference Documentation**: https://wiki.servarr.com/radarr/environment-variables

The pattern for Radarr environment variables is:
```
RADARR__CONFIGNAMESPACE__CONFIGITEM
```

Example: To set the log level, add:
```yaml
app-chart:
  deployment:
    containers:
      radarr:
        env:
          - name: RADARR__LOG__LEVEL
            value: "Info"
```

## Networking

### Gateway API (HTTPRoute)

The chart uses the Kubernetes Gateway API for ingress routing, providing a standard, portable way to configure traffic routing.

**Implementation:**

- **HTTPS Route**: Main application route configured on the `https` listener
  - Hostname: `radarr-k8s.orhayoun.com`
  - Gateway: `shared-platform-gateway` in `istio-system` namespace
  - Routes all traffic (`/`) to the `radarr-http` service on port 8080
  - Uses `PathPrefix` matching for flexible path routing

- **HTTP Redirect Route**: Automatic HTTP to HTTPS redirect
  - Configured on the `http` listener
  - Uses `RequestRedirect` filter to redirect all HTTP traffic to HTTPS
  - Returns HTTP 301 (permanent redirect) status code
  - Ensures all traffic is encrypted in transit

**Benefits:**
- Uses the GA (Generally Available) Gateway API standard
- Clean separation of HTTP and HTTPS routing logic
- Standard redirect pattern for enforcing HTTPS
- Portable across different Gateway implementations (Istio, NGINX, etc.)

**Configuration Location:**
- HTTPRoute configuration is in `values.yaml` under `app-chart.network.httpRoute`

### NetworkPolicy Egress Configuration

The NetworkPolicy allows broad egress access to the internet on ports 80, 443, and 8080.

**Rationale:**
- Radarr requires access to external indexers (Usenet indexers, torrent trackers, etc.) to search for movies
- Radarr needs to check for application updates from various sources
- Indexer and update server IP addresses are dynamic and can change frequently
- Limiting egress to specific IP addresses would be impractical and require constant maintenance
- The service would break if indexer IPs change and the NetworkPolicy isn't updated

**Configuration:**
- Egress allows traffic to `0.0.0.0/0` (all internet) on ports 80, 443, and 8080
- Excludes RFC1918 private ranges (10.42.0.0/16, 10.43.0.0/16, 192.168.0.0/16) to prevent cluster-internal conflicts
- Also allows access to local network `192.168.30.0/24` for local services

**Security Tradeoff:**
- This is an intentional security tradeoff for operational simplicity
- If the pod is compromised, it could potentially exfiltrate data over these ports
- The tradeoff is accepted because:
  - Radarr's functionality requires dynamic external access
  - Maintaining a whitelist of indexer IPs is operationally infeasible
  - Other security layers (NetworkPolicy ingress, AuthorizationPolicy, container hardening) provide defense-in-depth

## Security Features

The chart includes comprehensive security features. For detailed security analysis, see [SECURITY_REVIEW.md](./SECURITY_REVIEW.md).

### Key Security Features

- **NetworkPolicy**: Explicit allow-lists for both ingress and egress traffic
- **ServiceAccount token automount**: Disabled to reduce attack surface
- **Container hardening**: `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `readOnlyRootFilesystem: true`
- **Security profiles**: `seccompProfile: RuntimeDefault`, `appArmorProfile: RuntimeDefault`
- **Health probes**: Comprehensive startup/readiness/liveness probes
- **Resource limits**: CPU, memory, and ephemeral storage limits configured

### Service Links Disabled

The deployment explicitly sets `enableServiceLinks: false` to disable automatic Service environment variable injection.

**Rationale:**
- Prevents Kubernetes from automatically injecting environment variables for every Service in the namespace
- Avoids environment variable explosion and potential name collisions
- Reduces unnecessary environment variables that the application doesn't need
- This is the Kubernetes-supported way to disable Service links

**Configuration:**
- Set in `values.yaml` under `app-chart.deployment.enableServiceLinks: false`
- Applies to all pods in the deployment

## Monitoring

### ServiceMonitor

- Deployed to `monitoring` namespace
- Targets metrics endpoint on port 9100 (exportarr sidecar)
- Scrape interval: 10s (short interval for responsive alerting on media center services)
- Includes metric relabeling for service and component labels
- **ServiceMonitor is the source of truth** for Prometheus scraping (any `prometheus.io/scrape` annotations are ignored when using Prometheus Operator)

### PrometheusRule

- Comprehensive alert definitions
- Service-specific alerts:
  - `RadarrDown` - Service is down
  - `RadarrQueueHigh` - Wanted backlog is high
  - `RadarrMissingMoviesHigh` - Missing movies count is high
- Resource usage alerts (CPU, memory, storage)
- Authorization policy denial alerts

### Dashboard

- **Grafana dashboard ConfigMap** deployed to `monitoring` namespace
- Includes comprehensive panels for:
  - Application metrics (queue, missing movies, system status)
  - Resource usage (CPU, memory, ephemeral storage)
  - Health status and probe results
  - Network traffic and authorization policy denials
- Uses service-specific metrics with proper labels for filtering

**Resource Monitoring and Adjustment:**
- The Grafana dashboard provides real-time visibility into resource usage (CPU, memory, ephemeral storage)
- Resource requests and limits are monitored through the dashboard
- **Resources are adjusted based on actual usage patterns observed in Grafana**
- Current resource configuration:
  - Main container (radarr): 2Gi ephemeral storage limit
  - Exporter sidecar: 10Mi ephemeral storage limit
- Regular review of dashboard metrics guides resource limit adjustments to optimize performance and resource utilization

## Logging

### Logging Labels

The Radarr pod includes structured logging labels to enable log aggregation and filtering:

- `logging.kubernetes.io/component: media-center` - Identifies the component group
- `logging.kubernetes.io/service: radarr` - Identifies the specific service

These labels enable log aggregation systems (e.g., Loki, Elasticsearch, Fluentd) to filter and organize logs by component and service.

### Accessing Logs

Radarr runs in a **multi-container pod** with two containers:
- `radarr` - Main application container
- `exporter` - Exportarr sidecar container for metrics

#### View Main Container Logs

```bash
kubectl logs -n media-center -l app.kubernetes.io/name=radarr -c radarr
```

#### View Exporter Sidecar Logs

```bash
kubectl logs -n media-center -l app.kubernetes.io/name=radarr -c exporter
```

#### View All Container Logs

```bash
kubectl logs -n media-center -l app.kubernetes.io/name=radarr
```

#### Follow Logs (Real-time)

```bash
kubectl logs -n media-center -l app.kubernetes.io/name=radarr -f
```

### Log Levels

Radarr supports log level configuration via the `RADARR__LOG__LEVEL` environment variable.

Available log levels (from most verbose to least):
- `Trace` - Most detailed logging
- `Debug` - Debug information
- `Info` - Informational messages (default if not set)
- `Warn` - Warning messages
- `Error` - Error messages only

## Storage

### Persistent Volumes

- **Config PVC**: `radarr-config` (Longhorn, 1Gi, ReadWriteOnce)
  - Mounted at `/config` in the pod
  - Contains Radarr configuration, database, and metadata
  - Retained across Helm operations

### NFS Mounts

- **Media**: `/mnt/vol1/media-center/media/movies` (mounted at `/media`)
- **Media Old**: `/mnt/vol1/Media/videos/Movies` (mounted at `/media-old`)
- **Downloads**: `/mnt/vol1/media-center/downloads` (mounted at `/downloads`)
- **Backup**: `/mnt/vol1/media-center/backup/radarr` (mounted at `/backup`)

All NFS mounts use server: `snorlax.orhayoun.com`

### Temporary Storage

- **EmptyDir**: `/tmp` (1Gi size limit)
  - Used for temporary files
  - Ephemeral storage (cleared on pod restart)
  - **Best Practice**: The `sizeLimit` prevents node disk pressure by limiting ephemeral storage usage
  - Ephemeral storage is a schedulable/limitable resource in Kubernetes, making this an important operational control

## Key Differences from Sonarr

- **User ID**: 1013 (vs Sonarr's 1012)
- **Group ID**: 1011 (same as Sonarr)
- **Media Path**: `/mnt/vol1/media-center/media/movies` (vs tv_shows)
- **Missing Items Metric**: `missing_movies_total` (vs `missing_episodes_total`)
- **Alert Names**: `RadarrQueueHigh`, `RadarrMissingMoviesHigh` (vs Sonarr's cutoff unmet)
- **Exportarr Service Name**: "Radarr" (vs "Sonarr")

## Troubleshooting

### Service Not Starting

1. Check pod status:
   ```bash
   kubectl get pods -n media-center -l app.kubernetes.io/name=radarr
   ```

2. Check pod logs:
   ```bash
   kubectl logs -n media-center -l app.kubernetes.io/name=radarr -c radarr
   ```

3. Verify PVC is attached:
   ```bash
   kubectl get pvc -n media-center radarr-config
   ```

### PVC Issues

1. Verify PVC exists and is bound:
   ```bash
   kubectl get pvc -n media-center radarr-config
   ```

2. Check PVC events:
   ```bash
   kubectl describe pvc -n media-center radarr-config
   ```

### Network Issues

1. Verify NetworkPolicy allows traffic:
   ```bash
   kubectl get networkpolicy -n media-center
   kubectl describe networkpolicy -n media-center
   ```

2. Check HTTPRoute configuration:
   ```bash
   kubectl get httproute -n media-center
   ```

## References

- **Radarr Documentation**: https://wiki.servarr.com/radarr
- **Radarr Environment Variables**: https://wiki.servarr.com/radarr/environment-variables
- **Security Review**: See [SECURITY_REVIEW.md](./SECURITY_REVIEW.md) for detailed security analysis
- **Chart Dependencies**: See `Chart.yaml` for dependency versions
