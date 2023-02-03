#!/bin/sh
# shellcheck disable=SC2153

# path to script's execution directory
working_directory="$(pwd)"
# the name of the project
project_name="$(basename "${working_directory}")"
# target docker container name
pmate_container_name="pmate-${project_name}"

export PMATE_PORT="${PMATE_PORT:-2222}"
export PMATE_WORKSPACE="${PMATE_WORKSPACE:-"/pmate"}"
export PMATE_SESSION_NAME="pmate"
export PMATE_USER="pmate"
export PMATE_GROUP="mates"
export PMATE_MATES

pmate_check_ssh_keygen() {
  if ! command -v ssh-keygen > /dev/null
  then
    >&2 echo "ERROR: ssh-keygen could not be found"
    exit 1
  fi
}

pmate_check_sshd() {
  if ! command -v sshd > /dev/null
  then
    >&2 echo "ERROR: sshd could not be found"
    exit 1
  fi
}

pmate_check_tmux() {
  if ! command -v tmux > /dev/null
  then
    >&2 echo "ERROR: tmux could not be found"
    exit 1
  fi
}

pmate_check_keys() {
  if [ ! -f "${PMATE_WORKSPACE}/keys" ]
  then
    >&2 echo "ERROR: no SSH keys in '${PMATE_WORKSPACE}/keys'"
    exit 2
  fi
}

pmate_check_for_running_session() {
  if [ ! "$(docker ps -a -q -f name="${2}")" ] && [ "${1}" = "localhost" ]; then
    >&2 echo "No session to connect to."
    exit 1
  fi
}

pmate_ensure_user() {
  sed -i "/^[a-zA-Z0-9_\-]\+:x:${GROUP_ID}:/d" /etc/group
  sed -i "/^[a-zA-Z0-9_\-]\+:x:[0-9]\+:${GROUP_ID}:/d" /etc/passwd
  sed -i "/^[a-zA-Z0-9_\-]\+:x:${USER_ID}:/d" /etc/passwd
  echo "${PMATE_GROUP}:x:${GROUP_ID}:" >> /etc/group
  echo "${PMATE_USER}:x:${USER_ID}:${GROUP_ID}:Pair programming manager:${PMATE_WORKSPACE}:/bin/sh" >> /etc/passwd
  echo "${PMATE_USER}:$(date +%s)" | chpasswd 2> /dev/null
  mkdir -p "${PMATE_WORKSPACE}"
  chown -R "${USER_ID}":"${GROUP_ID}" "${PMATE_WORKSPACE}"
}

pmate_set_authorized_keys() {
  pmate_check_keys
  PMATE_MATES="$(cut -d ' ' -f 3 "${PMATE_WORKSPACE}/keys" | tr "\n" "," | sed "s/,$//")"
  SSH_PUBKEY_REGEXP="^ssh-rsa [0-9A-Za-z+\/=]\+ [0-9a-zA-Z:\-_]\+$"
  mkdir -p "${PMATE_WORKSPACE}/.ssh"
  grep -e "${SSH_PUBKEY_REGEXP}" "${PMATE_WORKSPACE}/keys" | while read -r key; do
    echo "command=\"$(which tmux) attach -t ${PMATE_SESSION_NAME}\" ${key}" >> "${PMATE_WORKSPACE}/.ssh/authorized_keys"
  done
  chown -R "${USER_ID}":"${GROUP_ID}" "${PMATE_WORKSPACE}/.ssh"
  chmod 500 "${PMATE_WORKSPACE}/.ssh"
  chmod 400 "${PMATE_WORKSPACE}/.ssh/authorized_keys"
}

pmate_set_tmux_configuration() {
  cat <<EOF > /etc/tmux.conf
set  -g default-terminal "tmux-256color"
set  -g mouse on
set  -g display-time 2000
set  -g history-limit 10000
setw -g alternate-screen on
set  -g focus-events on
set  -g status-left-style "bg=colour8"
set  -g status-right-style "bg=colour8"
set  -g status-style "bg=colour0"
set  -g status-left  "#{?client_prefix,#[bg=colour1],} #{session_name} "
set  -g status-right " with: ${PMATE_MATES} "
setw -g window-status-format " #[fg=colour8]#I#F #W"
setw -g window-status-current-format " #I#F#W"
EOF
}

pmate_set_ssh_daemon_configuration() {
  cat <<EOF > /etc/sshd_config
Protocol 2
Port 22
PubkeyAuthentication yes
PasswordAuthentication no
AllowTcpForwarding no
X11Forwarding no
AllowUsers ${PMATE_USER}
PrintMotd no
IgnoreUserKnownHosts yes
PermitRootLogin no
PermitEmptyPasswords no
EOF
}

pmate_start_tmux_session() {
  pmate_check_tmux
  pmate_set_tmux_configuration
  su -c "tmux new-session -d -s ${PMATE_SESSION_NAME} -c ${PMATE_WORKSPACE}/project" "${PMATE_USER}"
}

pmate_start_ssh_daemon() {
  pmate_check_ssh_keygen
  ssh-keygen -A > /dev/null
  pmate_check_sshd
  pmate_set_ssh_daemon_configuration
  mkdir -p /var/run/sshd
  chmod 0755 /var/run/sshd
  exec /usr/sbin/sshd -p "${PMATE_PORT}" -Def /etc/ssh/sshd_config
}

pmate_start() {
  if [ ! "$(docker ps -a -q -f name="${2}")" ]; then
    group_id=$(id -g)
    user_id=$(id -u)
    docker run \
      --detach \
      --rm \
      --hostname "${project_name}" \
      --name "${2}" \
      --publish "${PMATE_PORT}:${PMATE_PORT}" \
      --env GROUP_ID="${group_id}" \
      --env USER_ID="${user_id}" \
      --mount "type=bind,source=${working_directory},target=${PMATE_WORKSPACE}/project" \
      --mount "type=bind,source=${working_directory}/.authorized_keys,target=${PMATE_WORKSPACE}/keys" \
      "${1}" > /dev/null && \
    echo "New session in ${working_directory} started."
  else
    >&2 echo "Session already in progress."
    exit 1
  fi
}

pmate_status() {
  if [ "$(docker ps -a -q -f name="${1}")" ]; then
    echo "Running."
  else
    echo "Stopped."
    exit 1
  fi
}

pmate_stop() {
  if [ "$(docker ps -a -q -f name="${1}")" ]; then
    docker rm -fv "${1}" > /dev/null && \
    echo "Session in ${working_directory} stopped."
  else
    >&2 echo "No session to stop."
    exit 1
  fi
}

pmate_connect() {
  ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -p "${2}" "${PMATE_USER}@${1}"
}

pmate_help() {
  >&2 echo "unknown command '${1}'"
  >&2 echo
  >&2 echo "Usage: $(basename "${0}") COMMAND"
  >&2 echo "  status"
  >&2 echo "      Status of the session."
  >&2 echo "  start [IMAGE]"
  >&2 echo "      Starts a pair-programming session."
  >&2 echo "  stop"
  >&2 echo "      Stops a pair-programming session."
  >&2 echo "   connect [HOST] [PORT]"
  >&2 echo "      Connects to the pair-programming session running on HOST and PORT."
  exit 1
}

case $1 in
  e*)
    pmate_ensure_user
    pmate_set_authorized_keys
    pmate_start_tmux_session
    pmate_start_ssh_daemon
    ;;

  start)
    pmate_image_name=${2:-"silquenarmo/pmate:latest"}
    pmate_start "${pmate_image_name}" "${pmate_container_name}"
    ;;

  status)
    pmate_status "${pmate_container_name}"
    ;;

  stop)
    pmate_stop "${pmate_container_name}"
    ;;

  connect)
    host=${2:-localhost}
    port=${3:-"${PMATE_PORT}"}
    pmate_check_for_running_session "${host}" "${pmate_container_name}"
    pmate_connect "${host}" "${port}"
    ;;

  *)
    pmate_help "${1}"
    ;;
esac
