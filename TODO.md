# Radarr Chart TODO - Security Review Items to Investigate

This document tracks items from the security review that require investigation and potential documentation updates.

## Items Requiring Investigation

### 1. Istio AuthorizationPolicy mTLS Requirement

**Status:** ⚠️ Needs Investigation

**Issue:**
- AuthorizationPolicy uses `principals` (workload identity) for authentication
- Policies based on workload identity assume Istio is providing authenticated identities (typically via mTLS)
- If mTLS identity isn't established, policy intent may not match reality

**Investigation Needed:**
- [ ] Verify that mTLS is enabled for the `media-center` namespace
- [ ] Verify that mTLS is enabled at the workload level for Radarr pods
- [ ] Confirm that AuthorizationPolicy enforcement is working as expected
- [ ] Document the mTLS requirement in README.md
- [ ] Document how to verify mesh authentication posture

**References:**
- [Istio AuthorizationPolicy reference](https://istio.io/latest/docs/reference/config/security/authorization-policy/)
- [Istio security identity model](https://istio.io/latest/docs/reference/config/security/authorization-policy/)

**Location in values.yaml:**
- `app-chart.network.istio.authorizationPolicy.items.*.rules[].from[].source.principals`

---

### 2. ServiceMonitor `honorLabels: true` Configuration

**Status:** ⚠️ Needs Investigation

**Issue:**
- `honorLabels: true` is set in the ServiceMonitor configuration
- This allows target-provided labels to override Prometheus labels
- May cause label collision/poisoning in shared Prometheus setups

**Investigation Needed:**
- [ ] Determine if `honorLabels: true` is intentional or should be changed to default (false)
- [ ] Verify if Radarr/exportarr metrics expose labels that should be honored
- [ ] Check if there are any label conflicts in the Prometheus setup
- [ ] Document the decision and rationale in README.md

**References:**
- [Prometheus scrape configuration (`honor_labels`)](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)

**Location in values.yaml:**
- `app-chart.metrics.serviceMonitor.honorLabels: true`

---

## Notes

- All items are from the security review in `SECURITY_REVIEW.md`
- These are operational/clarity improvements, not security violations
- Once investigated, update README.md with findings and decisions
