FROM ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
        fontypython \
        fontconfig \
        inotify-tools \
        python-gi \
        x11-apps && \
    rm -rf /var/lib/apt/lists/*

# Build-time args identify the HOST user. The container runs AS that user
# (matching uid/gid) instead of root — so /etc/passwd inside the container
# genuinely reports $HOME as the real host home path, and every file the
# container creates in a bind-mounted host directory comes out owned by
# you on the host, not root. run.sh passes these automatically from
# `id -u` / `id -g` / `id -un` / `$HOME` at build time.
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG HOST_USER=fpuser
ARG HOST_HOME=/home/fpuser

RUN groupadd -g "${HOST_GID}" "${HOST_USER}" \
 && useradd -M -u "${HOST_UID}" -g "${HOST_GID}" -d "${HOST_HOME}" -s /bin/bash "${HOST_USER}"

# FontyPython (legacy Python2/wxGTK, written for old-school desktop
# layouts) assumes these exist. Pre-create + own them so it doesn't choke
# on first run. The ones that matter (.fonts, Resources/fonts,
# .fontypython) get bind-mounted over these at run time — see
# docker-compose.yml — so this is just a safety-net default.
RUN mkdir -p \
      "${HOST_HOME}/Desktop" \
      "${HOST_HOME}/Documents" \
      "${HOST_HOME}/Downloads" \
      "${HOST_HOME}/.config" \
      "${HOST_HOME}/.fonts" \
      "${HOST_HOME}/.fontypython" \
      "${HOST_HOME}/Resources/fonts" \
 && chown -R "${HOST_UID}:${HOST_GID}" "${HOST_HOME}"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER ${HOST_UID}:${HOST_GID}

ENTRYPOINT ["/entrypoint.sh"]
