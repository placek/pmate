#!/bin/sh

self=$(basename "${0}")
working_directory="$(pwd)"
pair_container_name="pmate-$(basename "${working_directory}")"
pair_image_name=${2:-"silquenarmo/pmate:latest"}
group_id=$(id -g)
user_id=$(id -u)
port=2222

case $1 in
  entrypoint)
    if ! command -v ssh-keygen &> /dev/null; then
      echo "ERROR: ssh-keygen could not be found"
      exit 1
    fi
    if ! command -v sshd &> /dev/null; then
      echo "ERROR: sshd could not be found"
      exit 1
    fi
    if ! command -v busybox &> /dev/null; then
      echo "ERROR: busybox could not be found"
      exit 1
    fi
    if ! command -v getent &> /dev/null; then
      echo "ERROR: getent could not be found"
      exit 1
    fi
    if ! command -v tmux &> /dev/null; then
      echo "ERROR: tmux could not be found"
      exit 1
    fi

    # set up the ssh daemon configuration
    cat <<EOF > /etc/sshd_config
Protocol 2
Port 22
PubkeyAuthentication yes
PasswordAuthentication no
AllowTcpForwarding no
X11Forwarding no
AllowUsers pair
PrintMotd no
IgnoreUserKnownHosts yes
PermitRootLogin no
PermitEmptyPasswords no
EOF

    # generate server-side key for passwordless authentication
    ssh-keygen -A > /dev/null

    # create users group
    if [[ ! -n "$(getent group ${GROUP_ID})" ]]; then
      addgroup -g ${GROUP_ID} users 2> /dev/null
    fi

    # add moderator
    if [[ ! -n "$(getent passwd ${USER_ID})" ]]; then
      adduser -D -u ${USER_ID} pair 2> /dev/null
    fi

    # collect data
    export PAIR_USER=$(getent passwd ${USER_ID} | cut -d: -f1)
    export PAIR_GROUP=$(getent group ${GROUP_ID} | cut -d: -f1)
    export PAIR_WORKSPACE="/workspace"
    export PAIR_USER_HOME="/home/${PAIR_USER}"
    export PAIR_SESSION_NAME="pmate"

    # create workspace
    mkdir -p ${PAIR_WORKSPACE}
    chown -R ${USER_ID}:${GROUP_ID} ${PAIR_WORKSPACE}

    # exit when no keys available under ${WORKSPACE}/authorized_keys
    if [ ! -f "${PAIR_WORKSPACE}/authorized_keys" ]; then
      >&2 echo "ERROR: no SSH keys in '${PAIR_WORKSPACE}/authorized_keys'"
      exit 2
    fi

    # set .ssh/authorized_keys
    echo "${PAIR_USER}:$(date +%s)" | chpasswd 2> /dev/null
    mkdir -p ${PAIR_USER_HOME}/.ssh
    cat ${PAIR_WORKSPACE}/authorized_keys | while read key; do
      echo "command=\"$(which tmux) attach -t ${PAIR_SESSION_NAME}\" ${key}" >> /home/${PAIR_USER}/.ssh/authorized_keys
    done
    chown -R ${USER_ID}:${GROUP_ID} ${PAIR_USER_HOME}/.ssh
    chmod 500 ${PAIR_USER_HOME}/.ssh
    chmod 400 ${PAIR_USER_HOME}/.ssh/*

    # start tmux named session "pmate" in deteached mode
    su -c "tmux new-session -d -s ${PAIR_SESSION_NAME} -c ${PAIR_WORKSPACE}/project" "${PAIR_USER}"

    # start ssh daemon
    exec /usr/sbin/sshd -p ${port} -Def /etc/ssh/sshd_config
    ;;

  sta*)
    docker run \
      --detach \
      --name ${pair_container_name} \
      --publish ${port}:${port} \
      --env GROUP_ID=${group_id} \
      --env USER_ID=${user_id} \
      -v ${working_directory}:/workspace/project \
      -v ${working_directory}/.authorized_keys:/workspace/authorized_keys \
      ${pair_image_name} > /dev/null && \
    echo "${self}: session in ${working_directory} started."
    ;;

  sto*)
    docker rm -fv ${pair_container_name} > /dev/null && \
    echo "${self}: session in ${working_directory} stopped."
    ;;

  con*)
    ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -p ${port} pair@${2}
    ;;

  *)
    echo "${self}: unknown command"
    echo
    echo "${self} start - starts a pair-programming session"
    echo "${self} stop  - stops a pair-programming session"
    exit 1
    ;;
esac
