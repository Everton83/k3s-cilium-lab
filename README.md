# k3s-cilium-lab

Everything needed to stand up the same k3s + Cilium + Gateway API stack
that runs on batata-server (`192.168.3.200`), on a fresh desktop or
server. This mirrors the
[Batata Lab Ledger](https://claude.ai/artifact/GCvjipTJcACJntfo2QXs9d) —
read that first for the reasoning; this file and its sibling folders are
the actual configuration.

## Is this box big enough?

batata-server is a 2008-era 4-core Xeon with 3.3GiB RAM — the sizing below
assumes hardware at least that capable, not more. If your box is
meaningfully bigger, most of the resource limits here are conservative
floors, not targets; if it's smaller or shared with other things, treat
every number below as a hard ceiling, not a suggestion.

| | |
|---|---|
| CPU | 4 vCPU minimum. Weak single-thread performance is fine; concurrent load is not — see "Sequencing rules" below. |
| Memory | 3.3 GiB minimum. k3s itself gets capped at 1536Mi via a systemd cgroup drop-in (`MemoryHigh`/`MemoryMax` on `k3s.service`) — that ceiling, not the host total, is the real budget for anything you add. |
| Disk | Not a constraint at any size tested (86G/265G free on the original). |

## What's here

| Folder | Runs on | What it is |
|---|---|---|
| `cilium/` | k3s | CNI + Gateway API + LoadBalancer (L2/LB-IPAM). Everything else in the cluster depends on this. |
| `gateway-api/` | k3s | The shared `Gateway` and per-app `HTTPRoute`s that expose things over HTTP(S) on the node IP. |
| `argocd/` | k3s | GitOps controller. Installed, healthy, not yet managing custom Applications — see its own README. |
| `ministack/` | **host**, not k3s | Local AWS emulator (S3/DynamoDB/SQS/60+ more) for Terraform practice, free and offline. |
| `gitlab-runner/` | **host**, not k3s | Native CI/CD executor for the Terraform project that targets MiniStack. |

MiniStack and GitLab Runner are deliberately **not** Kubernetes workloads
— both have bursty, unpredictable resource use, and putting either in the
1536Mi k3s cgroup is exactly the mistake this repo's incident log (below)
documents happening with something else.

Observability (Loki, Prometheus/VictoriaMetrics, Grafana) is intentionally
**absent** — a same-day attempt to run five Helm charts at once caused
real swap-thrashing and an unresponsive apiserver (incident 1 below). It's
deferred to a separate, dedicated box rather than retried here.

## Bring-up order

```
1. k3s itself           -- any recent k3s install works; this was built against v1.36
2. cilium/               -- CNI must exist before anything else schedules (./cilium/install.sh)
3. gateway-api/          -- needs Cilium's Gateway API CRDs, installed by the script above
4. argocd/                -- needs a Gateway listener + TLS secret for its route
5. ministack/            -- independent, host-level, any time
6. gitlab-runner/        -- independent, host-level; needs a GitLab project + runner token
```

Steps 2–4 are Terraform-managed in the source project this was extracted
from (`helm_release` + `kubernetes_manifest` resources pointed at these
same values files) if you'd rather apply them declaratively than run each
chart by hand — not included here since this repo is meant to stand alone.

## Capacity ledger

Running total of Kubernetes-side memory *requests* against the 1536Mi
cgroup ceiling. Limits run higher on every component — the lesson learned
the hard way (below) is that requests, not limits, are what to watch.

| Component | Runs on | Req | Limit |
|---|---|---:|---:|
| cilium (agent + envoy + operator) | k3s | ~224Mi | ~512Mi |
| coredns, metrics-server, local-path-provisioner | k3s | ~88Mi | ~224Mi |
| argocd (5 components) | k3s | ~165Mi | ~688Mi |
| whoami (demo app) | k3s | 8Mi | 32Mi |
| **k3s total** | | **~804Mi (52%)** | **~2890Mi (85% — see note)** |
| MiniStack | host | ~30MB RSS | 128M cap |
| gitlab-runner | host | ~20MB RSS | — |
| terraform CLI (transient) | host | ~300Mi spike, not resident | — |

The 85% limit figure is not a typo: this cluster runs comfortably with
limits that, summed, exceed the cgroup ceiling — because not everything
peaks at once. It's also exactly the kind of overcommit that turned into
real swap-thrashing three separate times before requests/limits were
tightened everywhere (see incidents below). Don't add a new component's
limit to this table without also asking whether it could plausibly peak
at the same time as something already here.

## Incident log

Full detail and root-cause writeups live in the
[Ledger](https://claude.ai/artifact/GCvjipTJcACJntfo2QXs9d) — summarized
here because each one is the reason something above is shaped the way it
is:

1. **Five ArgoCD Applications synced at once** → iowait 67–94%, apiserver
   TLS handshakes failing, load average 12.25. Caused by skipping the
   "one thing at a time" rule below. → observability moved off this box.
2. **A `kubectl get pods -A -o wide` run to check on incident 1 made it
   worse** — landed while k3s's SQLite-backed datastore was already
   issuing multi-second writes. → once `kubectl` starts timing out, stop
   using it (see rules below).
3. **Deleting an ArgoCD `Application` didn't delete its Deployments** —
   no cascade finalizer was set, so Grafana and kube-state-metrics kept
   restart-looping under kubelet's control after their Applications were
   already gone.
4. **Every CI job failed instantly with an opaque error** — root cause
   was two host-level misconfigurations for the `gitlab-runner` Linux
   user (wrong shell, and a `.bash_logout` that fails without a TTY), not
   anything about the pipeline or the Terraform code. See
   `gitlab-runner/README.md` for the fix and how it was actually found
   (`strace -f`, since GitLab Runner's own logs never showed the real
   cause even at debug level).

## Sequencing rules

- **Sync or install one thing at a time in GitOps/Kubernetes work, full
  stop.** Incident 1 happened because this rule existed in an earlier
  draft of this plan and got skipped in practice.
- Never run `terraform apply` (aws provider, against MiniStack) at the
  same time as an ArgoCD sync or a Helm upgrade — both are documented to
  spike memory independently on hardware this size.
- The moment `kubectl` starts timing out, stop issuing more `kubectl`
  commands, including read-only ones. Switch to `free -h`, `vmstat 1`,
  and `k3s crictl` (all bypass the apiserver) until it's confirmed
  responsive again.
- If `cilium` or `cilium-envoy` gets restarted for any reason, restart
  `cilium-operator` right after — the Gateway API listener drops until
  you do, a rough edge this chart version hits on every upgrade.
- A hostname-less `HTTPRoute` or `Gateway` listener is a catch-all for
  every other hostname too — see the comments in `gateway-api/` for the
  gotcha this actually caused here.
- MiniStack and gitlab-runner don't show up in `kubectl top` — they're
  host processes. Include them in any `free -h` review.
- Any new shell-executor CI user needs a real login shell *and* a
  harmless `~/.bash_logout` — see `gitlab-runner/README.md`.
- When a tool's error is generic and its own logs won't say more even at
  debug level, reach for `strace -f -p <pid>` on the parent process
  before guessing at config one variable at a time.
