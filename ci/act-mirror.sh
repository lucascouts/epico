#!/usr/bin/env bash
# Runs one CI job locally on the runner-mirror image, from caches: the image
# from the local store (--pull=false), each action from ~/.cache/act once it is
# there (--action-offline-mode), and the job's apt and npm downloads from named
# volumes kept between runs — so a second run downloads nothing it already has.
# The checks themselves run exactly as on the runner.
#
#   docker build -t epico-act:26.04 ci/act-ubuntu-26.04     once
#   ci/act-mirror.sh <job>                                  from a clean clone
#
# Each job gets its own volumes: apt holds a lock on its lists, so two jobs
# sharing one volume would fail each other when run at the same time.
# Exit: act's own; 2 on bad usage.

set -euo pipefail

JOB="${1-}"
case "$JOB" in
  '' | -*) echo "usage: ci/act-mirror.sh <job>   (act -l lists the jobs)" >&2; exit 2 ;;
  *[!A-Za-z0-9_-]*) echo "act-mirror.sh: a job id is letters, digits, '-' and '_': $JOB" >&2; exit 2 ;;
esac
command -v act >/dev/null || { echo "act-mirror.sh: act is required" >&2; exit 2; }

vol="epico-act-$JOB"
exec act -P ubuntu-26.04=epico-act:26.04 --pull=false --action-offline-mode \
  --container-options "--volume $vol-apt-lists:/var/lib/apt/lists --volume $vol-apt-archives:/var/cache/apt/archives --volume $vol-npm:/home/runner/.npm" \
  -j "$JOB"
