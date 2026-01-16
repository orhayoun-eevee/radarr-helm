# Radarr Security and Configuration Review

## ✅ What Is Good

* **NetworkPolicy applies explicit allow-lists for both ingress and egress**

  * **What is done well:** `policyTypes: [Ingress, Egress]` with specific `from` / `to` rules and ports.
  * **Why it is good:** Once a Pod is selected by a NetworkPolicy, traffic is effectively restricted to what policies allow; this is a core mechanism to reduce lateral movement and data exfiltration risk.
  * **Documentation:** Kubernetes NetworkPolicy concept docs. ([Kubernetes][1])

* **ServiceAccount token automount is disabled**

  * **What is done well:** `automountServiceAccountToken: false` on the ServiceAccount and again on the Pod spec.
  * **Why it is good:** Reduces blast radius if the workload is compromised by avoiding automatic in-cluster API credentials in the filesystem.
  * **Documentation:** Kubernetes ServiceAccounts and configuring ServiceAccounts for Pods. ([Kubernetes][2])

* **Strong container and pod hardening settings**

  * **What is done well:** `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `readOnlyRootFilesystem: true`, `seccompProfile: RuntimeDefault`, `appArmorProfile: RuntimeDefault`.
  * **Why it is good:** Aligns with Kubernetes security mechanisms for reducing kernel attack surface and privilege escalation opportunities.
  * **Documentation:** SecurityContext task guide; Seccomp; AppArmor. ([Kubernetes][3])

* **Health probes are comprehensive (startup/readiness/liveness)**

  * **What is done well:** Both containers have `startupProbe`, `readinessProbe`, and `livenessProbe`.
  * **Why it is good:** Startup probes prevent premature liveness kills for slow-starting apps; readiness gates traffic until the app is actually ready.
  * **Documentation:** Probes task + concept docs. ([Kubernetes][4])

* **Resource requests/limits include ephemeral-storage**

  * **What is done well:** CPU/memory requests+limits are set, and ephemeral storage limits/requests are explicitly configured; `emptyDir.sizeLimit` is used for `/tmp`.
  * **Why it is good:** Makes scheduling more predictable and prevents node disk pressure surprises (ephemeral storage is a schedulable/limitable resource).
  * **Documentation:** Resource management; local ephemeral storage. ([Kubernetes][5])

* **Good operability knobs: `enableServiceLinks: false`**

  * **What is done well:** Explicitly disables Service env-var injection.
  * **Why it is good:** Avoids env var explosion and potential name collisions; Kubernetes documents this as the supported way to disable Service links.
  * **Documentation:** Kubernetes "Accessing the Service" docs. ([Kubernetes][6])

* **Gateway API usage looks clean and production-shaped**

  * **What is done well:** Separate HTTPRoute for HTTPS routing and HTTP→HTTPS redirect using `RequestRedirect`.
  * **Why it is good:** Uses the GA HTTPRoute API and standard redirect pattern.
  * **Documentation:** Gateway API HTTPRoute + redirect guide. ([Kubernetes Gateway API][7])

* **Prometheus Operator integration is first-class**

  * **What is done well:** `ServiceMonitor` and `PrometheusRule` are defined (instead of ad-hoc annotations only).
  * **Why it is good:** This is the intended, Kubernetes-native approach when using Prometheus Operator CRDs.
  * **Documentation:** Prometheus Operator docs and API reference. ([Prometheus Operator][8])

* **PVC lifecycle intent is explicit**

  * **What is done well:** `helm.sh/resource-policy: keep` on the PVC.
  * **Why it is good:** Prevents accidental data loss on uninstall/rollback/upgrade operations that would otherwise delete the PVC.
  * **Documentation:** Helm docs on `helm.sh/resource-policy: keep`. ([helm.sh][9])

---

## ⚠️ What Can Be Improved

* **PDB with `minAvailable: 1` and `replicas: 1` can block node drains (you said it's OK — just be aware of the operational behavior)**

  * **Problem / Risk:** With 1 replica, `minAvailable: 1` means *zero voluntary evictions* are allowed; `kubectl drain` may hang waiting.
  * **Why it matters:** This becomes an ops-footgun during node maintenance if you forget this budget exists.
  * **Recommended change:** Consider setting `spec.unhealthyPodEvictionPolicy: AlwaysAllow` to avoid drains being blocked by an unhealthy pod (keeps your "1 replica must stay up" stance, but improves maintenance behavior when the pod is already broken).
  * **Tradeoffs / Complexity:** Slightly more nuanced eviction behavior; still won't allow draining a healthy single replica, but avoids deadlock when the pod is unhealthy.
  * **Documentation:** PDB semantics + disruptions guidance. ([Kubernetes][10])

* **Helm `resource-policy: keep` makes the PVC orphaned (lifecycle + upgrades need a runbook)**

  * **Problem / Risk:** Helm will stop managing a kept resource; it won't be updated or deleted by Helm anymore, and can cause surprises with `helm install --replace` patterns.
  * **Why it matters:** Drift and confusing ownership during upgrades/migrations; the next chart version may assume it "owns" PVC fields it can no longer reconcile.
  * **Recommended change:** Keep the annotation if you want (it's valid), but document this explicitly in chart README/runbook and consider supporting an `existingClaim` value pattern so operators can intentionally bind to a pre-created PVC (common approach for persistent data).
  * **Tradeoffs / Complexity:** Adds a small amount of values/templating complexity, but reduces "mystery ownership" during lifecycle events.
  * **Documentation:** Helm resource policy `keep` behavior and the orphaning warning. ([helm.sh][9])

* **NetworkPolicy egress is broad (`0.0.0.0/0` on 80/443/8080)**

  * **Problem / Risk:** This permits general outbound internet access (minus RFC1918 ranges). If the pod is compromised, it can exfiltrate over common ports.
  * **Why it matters:** Egress is typically the easiest path for data theft; NetworkPolicies are one of the few native controls to constrain it.
  * **Recommended change:** Narrow the `ipBlock` to known upstreams where possible, or route egress through a controlled gateway (if your platform already uses one). At minimum, consider whether port `8080` to the public internet is needed.
  * **Tradeoffs / Complexity:** Tight egress policies require you to know dependencies and keep them updated; operational overhead increases, but security posture improves.
  * **Documentation:** NetworkPolicy purpose/behavior (Kubernetes L3/L4 control model). ([Kubernetes][1])

* **Prometheus scraping signals are mixed (`prometheus.io/scrape: "false"` but you also define a ServiceMonitor)**

  * **Problem / Risk:** The annotation won't affect Prometheus Operator scraping when using ServiceMonitors, but it can confuse humans and any non-Operator Prometheus setups.
  * **Why it matters:** "Conflicting intent" slows incident response and handoffs.
  * **Recommended change:** If ServiceMonitor is your standard, remove the annotation (or ensure your org has a clear convention: "annotations ignored; ServiceMonitor is source of truth").
  * **Tradeoffs / Complexity:** Minimal change; mostly improves clarity.
  * **Documentation:** Prometheus Operator model (ServiceMonitors selected via label/namespace selectors). ([Prometheus Operator][11])

* **Istio AuthorizationPolicy uses `principals` (ensure mTLS identity is actually in effect)**

  * **Problem / Risk:** Policies based on workload identity assume Istio is providing authenticated identities (typically via mTLS). If identity isn't established, policy intent may not match reality.
  * **Why it matters:** You might think access is constrained to specific service accounts, but enforcement may be weaker if identity isn't present.
  * **Recommended change:** Verify mesh authentication posture for these workloads (at least at the namespace/workload level) and ensure your security model matches the identity fields you're using.
  * **Tradeoffs / Complexity:** Operational verification/config depends on your Istio setup; the policy itself is fine.
  * **Documentation:** Istio AuthorizationPolicy reference and security identity model. ([Istio][12])

* **Deployment `Recreate` strategy (you stated it's required due to PVC attach limits) — ensure you've accepted the downtime characteristics**

  * **Problem / Risk:** `Recreate` terminates old Pods before new ones come up, which can cause downtime during upgrades.
  * **Why it matters:** Even with 1 replica, this formalizes downtime as part of the rollout behavior.
  * **Recommended change:** Keep `Recreate` if the storage constraint truly requires it, but document the expected downtime and ensure probes/terminationGracePeriod are tuned for clean shutdown/startup (you already have good probe coverage).
  * **Tradeoffs / Complexity:** No added complexity; mainly operational clarity.
  * **Documentation:** Deployment controller behavior and updates model. ([Kubernetes][13])

---

## ❌ What Violates Best Practices (If Any)

* **No clear best-practice violations found** based on the manifests provided.

  * Most key security and operability controls are explicitly set (which is typically where "hard" violations show up).

---

## 🧠 Optional Enhancements (Nice-to-Have)

* **Add a short lifecycle note for single-replica maintenance**

  * Suggestion: Put a brief runbook snippet in chart docs: "PDB prevents voluntary eviction; use a controlled maintenance procedure" and explicitly tie it to your accepted single-replica + PVC limitation.
  * Value: Reduces operator surprise.
  * Documentation basis: PDB/node drain semantics. ([Kubernetes][10])

* **Review `honorLabels: true` in ServiceMonitor**

  * Suggestion: Keep if you intentionally allow target-provided labels to win; otherwise consider default behavior to avoid label collision/poisoning in shared Prometheus setups.
  * Value: Safer multi-tenant metrics hygiene.
  * Documentation basis: Prometheus scrape configuration (`honor_labels`). ([Prometheus][14])

---

## 📚 References

* Kubernetes Network Policies: ([Kubernetes][1])
* Kubernetes PodDisruptionBudget task + disruptions behavior: ([Kubernetes][10])
* Kubernetes Security Contexts: ([Kubernetes][3])
* Kubernetes Seccomp: ([Kubernetes][15])
* Kubernetes AppArmor: ([Kubernetes][16])
* Kubernetes Probes: ([Kubernetes][4])
* Kubernetes Resource Management + Ephemeral Storage: ([Kubernetes][5])
* Kubernetes `enableServiceLinks`: ([Kubernetes][6])
* Kubernetes Deployments / updates: ([Kubernetes][13])
* Helm `helm.sh/resource-policy: keep`: ([helm.sh][9])
* Gateway API HTTPRoute + redirect guide: ([Kubernetes Gateway API][7])
* Prometheus Operator overview / API reference: ([Prometheus Operator][8])
* Prometheus configuration (`honor_labels`): ([Prometheus][14])
* Istio AuthorizationPolicy + security concepts: ([Istio][12])

[1]: https://kubernetes.io/docs/concepts/services-networking/network-policies/?utm_source=chatgpt.com "Network Policies"
[2]: https://kubernetes.io/docs/concepts/security/service-accounts/?utm_source=chatgpt.com "Service Accounts"
[3]: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/?utm_source=chatgpt.com "Configure a Security Context for a Pod or Container"
[4]: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/?utm_source=chatgpt.com "Configure Liveness, Readiness and Startup Probes"
[5]: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/?utm_source=chatgpt.com "Resource Management for Pods and Containers"
[6]: https://kubernetes.io/docs/tutorials/services/connect-applications-service/?utm_source=chatgpt.com "Connecting Applications with Services"
[7]: https://gateway-api.sigs.k8s.io/api-types/httproute/?utm_source=chatgpt.com "HTTPRoute"
[8]: https://prometheus-operator.dev/docs/getting-started/introduction/?utm_source=chatgpt.com "Introduction - Prometheus Operator"
[9]: https://helm.sh/docs/howto/charts_tips_and_tricks?utm_source=chatgpt.com "Chart Development Tips and Tricks"
[10]: https://kubernetes.io/docs/tasks/run-application/configure-pdb/?utm_source=chatgpt.com "Specifying a Disruption Budget for your Application"
[11]: https://prometheus-operator.dev/docs/api-reference/api/?utm_source=chatgpt.com "API reference - Prometheus Operator"
[12]: https://istio.io/latest/docs/reference/config/security/authorization-policy/?utm_source=chatgpt.com "Authorization Policy"
[13]: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/?utm_source=chatgpt.com "Deployments"
[14]: https://prometheus.io/docs/prometheus/latest/configuration/configuration/?utm_source=chatgpt.com "Configuration"
[15]: https://kubernetes.io/docs/reference/node/seccomp/?utm_source=chatgpt.com "Seccomp and Kubernetes"
[16]: https://kubernetes.io/docs/tutorials/security/apparmor/?utm_source=chatgpt.com "Restrict a Container's Access to Resources with AppArmor"
