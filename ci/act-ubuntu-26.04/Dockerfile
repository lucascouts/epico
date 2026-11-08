# Local mirror of GitHub's ubuntu-26.04 runner for `act`: no published act
# image tracks 26.04 (catthehacker ships act-24.04 and act-latest = 24.04), and
# 24.04's GNU coreutils hid a lock race that 26.04's uutils mkdir exposed.
# What it does not mirror: the runner's preinstalled toolset beyond what
# .github/workflows/shell.yml installs itself.
#
#   docker build -t epico-act:26.04 ci/act-ubuntu-26.04
#   ci/act-mirror.sh bats      (act on this image, from the local caches)
FROM ubuntu:26.04@sha256:c098726dd9b9733f3e885f8de0ef375206a311b0a317eadc40d347b1115fb944

# nodejs runs the JavaScript actions (actions/checkout); npm installs Claude
# Code for plugin-validate; sudo, because every job installs its tools with it.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates git sudo nodejs npm \
 && rm -rf /var/lib/apt/lists/*

# The runner's user is not root: as root, the suite's unreadable-file cases
# cannot be refused and fail as false reds.
RUN useradd -m -s /bin/bash runner \
 && printf 'runner ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/runner \
 && chmod 0440 /etc/sudoers.d/runner

# Keep what apt downloads, as the runner's VM does — the Docker base deletes
# every .deb after an install — and give npm its cache directory as the runner's
# user: ci/act-mirror.sh mounts both as volumes, and a new volume takes the
# owner of the directory it lands on.
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
 && mkdir -p /home/runner/.npm \
 && chown runner:runner /home/runner/.npm
USER runner
ENV NPM_CONFIG_PREFIX=/home/runner/.npm-global \
    PATH=/home/runner/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8
WORKDIR /home/runner
