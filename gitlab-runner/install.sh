#!/usr/bin/env bash
# Installs a native GitLab Runner (shell executor) as a host service --
# deliberately NOT a k3s workload. See ../README.md: a CI runner's resource
# use is bursty and unpredictable, exactly what a memory-tight cluster
# can't absorb.
#
# Usage: ./install.sh <gitlab-url> <runner-auth-token> [description]
#   <runner-auth-token> is the glrt-... token from the project's
#   Settings > CI/CD > Runners > "New project runner" page, NOT the old
#   shared registration-token flow.
set -euo pipefail

GITLAB_URL="${1:?usage: install.sh <gitlab-url> <runner-token> [description]}"
RUNNER_TOKEN="${2:?usage: install.sh <gitlab-url> <runner-token> [description]}"
DESCRIPTION="${3:-$(hostname) (native, host shell executor)}"

sudo curl -fsSL -o /usr/local/bin/gitlab-runner \
  "https://gitlab-runner-downloads.s3.amazonaws.com/v17.11.0/binaries/gitlab-runner-linux-amd64"
sudo chmod +x /usr/local/bin/gitlab-runner

# Pinned to v17.11.0 rather than latest: a same-day repro against 19.3.3
# showed identical failures for the real bug this script also fixes below
# (it's unrelated to the runner version), so the pin is just "known good,"
# not load-bearing -- revisit if there's a reason to.

if ! id gitlab-runner &>/dev/null; then
  # Needs a REAL login shell. The shell executor runs every job through
  # `bash -l`, so /usr/sbin/nologin here breaks every single job with an
  # opaque "prepare environment: exit status 1" -- see the fix below for
  # the other half of this same class of bug.
  sudo useradd --system --shell /bin/bash --home-dir /home/gitlab-runner --create-home gitlab-runner
fi

# The other half: Ubuntu's default ~/.bash_logout calls `clear_console -q`
# on every login-shell exit to blank the screen "for privacy." With no
# controlling TTY (always true in CI), clear_console exits 1, and THAT
# becomes the whole job's exit code -- independent of anything the job
# itself did. Scoped to this user only, not /etc/skel.
sudo -u gitlab-runner sed -i \
  's#\[ -x /usr/bin/clear_console \] && /usr/bin/clear_console -q$#[ -x /usr/bin/clear_console ] \&\& /usr/bin/clear_console -q || true#' \
  /home/gitlab-runner/.bash_logout

sudo install -m 644 "$(dirname "$0")/gitlab-runner.service" /etc/systemd/system/gitlab-runner.service
sudo systemctl daemon-reload
sudo systemctl enable gitlab-runner
sudo systemctl start gitlab-runner

sudo gitlab-runner register \
  --non-interactive \
  --url "$GITLAB_URL" \
  --token "$RUNNER_TOKEN" \
  --executor "shell" \
  --description "$DESCRIPTION"

sudo systemctl restart gitlab-runner
sudo systemctl status gitlab-runner --no-pager -l | head -8
