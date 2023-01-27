#!/bin/sh

# name of the script
self=$(basename "${0}")
# path to script's execution directory
working_directory="$(pwd)"
# the name of the project
project_name="$(basename "${working_directory}")"
# target docker container name
pmate_container_name="pmate-${project_name}"
# group_id and user_id of the user sharing session
group_id=$(id -g)
user_id=$(id -u)
# allowed .authorized_keys format
ssh_pubkey_regexp="^ssh-rsa [0-9A-Za-z+\/=]\+ [0-9a-zA-Z:\-_]\+$"

export PMATE_PORT=2222
export PMATE_WORKSPACE="/pmate"
export PMATE_SESSION_NAME="pmate"
export PMATE_USER="pmate"
export PMATE_GROUP="mates"
export PMATE_USER_HOME="/home/${PMATE_USER}"
export PMATE_MATES

case $1 in
  entrypoint)
    if ! command -v ssh-keygen > /dev/null; then
      echo "ERROR: ssh-keygen could not be found"
      exit 1
    fi
    if ! command -v sshd > /dev/null; then
      echo "ERROR: sshd could not be found"
      exit 1
    fi
    if ! command -v busybox > /dev/null; then
      echo "ERROR: busybox could not be found"
      exit 1
    fi
    if ! command -v getent > /dev/null; then
      echo "ERROR: getent could not be found"
      exit 1
    fi
    if ! command -v tmux > /dev/null; then
      echo "ERROR: tmux could not be found"
      exit 1
    fi

    # generate server-side key for passwordless authentication
    ssh-keygen -A > /dev/null

    # ensure group and user_id
    deluser guest 2> /dev/null # FIXME! nasty hack

    if [ -n "$(getent passwd "${USER_ID}")" ]; then
      user="$(getent passwd "${USER_ID}" | cut -d: -f1)"
      deluser --remove-home "${user}" 2> /dev/null
    fi

    if [ -n "$(getent group "${GROUP_ID}")" ]; then
      group="$(getent group "${GROUP_ID}" | cut -d: -f1)"
      delgroup "${group}" 2> /dev/null
    fi

    addgroup -g "${GROUP_ID}" "${PMATE_GROUP}" 2> /dev/null
    adduser -D -u "${USER_ID}" "${PMATE_USER}" 2> /dev/null
    echo "${PMATE_USER}:$(date +%s)" | chpasswd 2> /dev/null
    mkdir -p "${PMATE_USER_HOME}/.ssh"

    # set up the ssh daemon configuration
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

    # create workspace
    mkdir -p ${PMATE_WORKSPACE}
    chown -R "${USER_ID}":"${GROUP_ID}" ${PMATE_WORKSPACE}

    # exit when no keys available under ${WORKSPACE}/keys
    if [ ! -f "${PMATE_WORKSPACE}/keys" ]; then
      >&2 echo "ERROR: no SSH keys in '${PMATE_WORKSPACE}/keys'"
      exit 2
    fi

    # list of mates
    PMATE_MATES="$(cut -d ' ' -f 3 "${PMATE_WORKSPACE}/keys" | tr "\n" "," | sed "s/,$//")"

    # set up the tmux configuration
    cat <<EOF > /etc/tmux.conf
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

    # set .ssh/authorized_keys
    grep -e "${ssh_pubkey_regexp}" "${PMATE_WORKSPACE}/keys" | while read -r key; do
      echo "command=\"$(which tmux) attach -t ${PMATE_SESSION_NAME}\" ${key}" >> "${PMATE_USER_HOME}/.ssh/authorized_keys"
    done
    chown -R "${USER_ID}":"${GROUP_ID}" "${PMATE_USER_HOME}/.ssh"
    chmod 500 "${PMATE_USER_HOME}/.ssh"
    chmod 400 "${PMATE_USER_HOME}/.ssh/authorized_keys"

    # start tmux named session in deteached mode
    su -c "tmux new-session -d -s ${PMATE_SESSION_NAME} -c ${PMATE_WORKSPACE}/project" "${PMATE_USER}"

    # start ssh daemon
    exec /usr/sbin/sshd -p ${PMATE_PORT} -Def /etc/ssh/sshd_config
    ;;

  start)
    if [ ! "$(docker ps -a -q -f name="${pmate_container_name}")" ]; then
      pmate_image_name=${2:-"silquenarmo/pmate:latest"}
      docker run \
        --detach \
        --rm \
        --hostname "${project_name}" \
        --name "${pmate_container_name}" \
        --publish ${PMATE_PORT}:${PMATE_PORT} \
        --env GROUP_ID="${group_id}" \
        --env USER_ID="${user_id}" \
        --mount "type=bind,source=${working_directory},target=${PMATE_WORKSPACE}/project" \
        --mount "type=bind,source=${working_directory}/.authorized_keys,target=${PMATE_WORKSPACE}/keys" \
        "${pmate_image_name}" > /dev/null && \
      echo "${self}: new session in ${working_directory} started."
    else
      echo "${self}: session already in progress."
      exit 1
    fi
    ;;

  status)
    if [ "$(docker ps -a -q -f name="${pmate_container_name}")" ]; then
      echo "${self}: running."
    else
      echo "${self}: stopped."
      exit 1
    fi
    ;;

  stop)
    if [ "$(docker ps -a -q -f name="${pmate_container_name}")" ]; then
      docker rm -fv "${pmate_container_name}" > /dev/null && \
      echo "${self}: session in ${working_directory} stopped."
    else
      echo "${self}: no session to stop."
      exit 1
    fi
    ;;

  connect)
    host=${2:-localhost}
    if [ ! "$(docker ps -a -q -f name="${pmate_container_name}")" ] && [ "${host}" = "localhost" ]; then
      echo "${self}: no session to connect to. Run '${self} start'."
      exit 1
    fi
    ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -p ${PMATE_PORT} "${PMATE_USER}@${host}"
    ;;

  *)
    echo "${self}: unknown command '${1}'"
    echo
    echo "${self} status"
    echo "    Status of the session."
    echo "${self} start"
    echo "    Starts a pair-programming session."
    echo "${self} stop"
    echo "    Stops a pair-programming session."
    echo "${self} connect [host]"
    echo "    Connects to the pair-programming session running on host. By default connects to localhost."
    exit 1
    ;;
esac
