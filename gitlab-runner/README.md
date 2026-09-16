# GitLab Runner

Native, host-level CI/CD executor — not a k3s workload. A runner's
resource use is bursty and unpredictable (a `terraform apply` alone spikes
~270–350Mi RSS), exactly what already destabilized this box once when
stacked with other work; see the Ledger's incident log.

## Install

```bash
./install.sh https://gitlab.com glrt-xxxxxxxxxxxxxxxxxxxx "my-server (native, host shell executor)"
```

The token is a **runner authentication token** (`glrt-...`) from the
target project's **Settings > CI/CD > Runners > New project runner** page
— not the old shared registration-token flow, which newer GitLab versions
reject.

## Gotcha this script already works around

Every job run through the shell executor executes as a **login shell**
(`bash -l`). Two things about that broke every single job here with the
same opaque error, independent of the job's own content:

1. **The runner's own Linux user needs a real shell.** `/usr/sbin/nologin`
   (a sensible default for most service accounts) makes every job fail
   instantly.
2. **`~/.bash_logout` runs when that login shell exits.** Ubuntu's default
   one calls `clear_console -q` to blank the screen "for privacy" — which
   fails with no controlling TTY (always true in CI), and *that* exit
   code becomes the whole job's exit code. `install.sh` patches this one
   line for the `gitlab-runner` user only, not `/etc/skel` or anyone
   else's shell.

Both show up identically: `ERROR: Job failed: prepare environment: exit
status 1`, duration effectively zero, with GitLab Runner never surfacing
the real cause in its own logs at any log level — including a completely
minimal `echo hi` job. If you hit this on a *different* host than the one
this repo was built for, `strace -f -p <gitlab-runner-pid>` while
retriggering a job is the fastest way to confirm it's the same thing
rather than a new bug.

## Verify

```bash
sudo systemctl status gitlab-runner
```
Then push a trivial commit to a project this runner is registered for and
watch `sudo journalctl -u gitlab-runner -f` for `Job succeeded`.
