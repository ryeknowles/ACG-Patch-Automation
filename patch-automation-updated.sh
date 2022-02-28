#!/bin/bash
set -e
export VM_NAME=consolo-psql-bastion
export PROJECT_ID=consolo-staging-app-wsky
export VM_ZONE=us-east4-a
export VM_PORT=22
export SOURCE_DB_LOCAL_IP=10.4.21.122
export SOURCE_DB_LOCAL_PORT=5432
export VERIFY_CONNECTIVITY=true

function verify_connectivity_to_source_db {
  if [[ "${VERIFY_CONNECTIVITY}" = true ]]; then
    if [[ $- =~ e ]]; then
      USE_E=true
      set +e
    fi

    NETCAT=$(which nc)
    if [[ -n "${NETCAT}" ]]; then
      echo "Verifying connectivity via netcat command to source DB: IP ${SOURCE_DB_LOCAL_IP} port ${SOURCE_DB_LOCAL_PORT}"
      nc -zv "${SOURCE_DB_LOCAL_IP}" "${SOURCE_DB_LOCAL_PORT}" &> /dev/null
      NC_RES=$?
      if (( NC_RES == 0 )); then
        echo "Connection to source DB verified"
      else
        echo "Connection refused, please verify that the machine you are using to run the script can connect to the source database at ${SOURCE_DB_LOCAL_IP}:${SOURCE_DB_LOCAL_PORT}"
        exit $NC_RES
      fi
    else
      echo "Verifying connectivity via /dev/tcp command to source DB: IP ${SOURCE_DB_LOCAL_IP} port ${SOURCE_DB_LOCAL_PORT}"
      DEV_TCP_CMD="cat < /dev/null > /dev/tcp/${SOURCE_DB_LOCAL_IP}/${SOURCE_DB_LOCAL_PORT}"
      timeout 5 bash -c "${DEV_TCP_CMD}" &> /dev/null
      DEV_TCP_RES=$?
        if (( DEV_TCP_RES == 0 )); then
          echo "Connection to source DB verified"
        else
          echo "Connection refused, please verify that the machine you are using to run the script can connect to the source database at ${SOURCE_DB_LOCAL_IP}:${SOURCE_DB_LOCAL_PORT}"
          exit $DEV_TCP_RES
        fi
    fi

    if [[ "$USE_E" = true ]]; then
      set -e
    fi
  fi
}


function existing_instance {
  # For the SSH tunnel to work, the ‘GatewayPorts’ parameter must be set to ‘yes’
  # Uncomment the lines below to update the configuration and restart the SSH service.
  # If you are reusing a VM you already used for a tunnel on a different migration job, there is no need to uncomment.
  # If you do not wish to make this change, create a new VM instead.
  # gcloud compute ssh "${VM_NAME}" --zone="${VM_ZONE}" --project="${PROJECT_ID}" -- 'if ! grep -q "^GatewayPorts yes" /etc/ssh/sshd_config; then sudo sed -i "s/GatewayPorts\ no/#GatewayPorts\ no/g" /etc/ssh/sshd_config && echo "GatewayPorts yes" | sudo tee -a /etc/ssh/sshd_config && sudo service ssh restart; fi'

  echo "Looking for existing SSH tunnel between the source and the VM on port '${VM_PORT}'"

  EXISTING_TUNNEL_PIDS_STRING="$(pgrep -f "ssh .* \-f \-N \-R ${VM_PORT}:${SOURCE_DB_LOCAL_IP}:${SOURCE_DB_LOCAL_PORT}" | tr '\n' ' ' | sed 's/ *$//g')"
  EXISTING_TUNNEL_PIDS_COUNT=$(echo "${EXISTING_TUNNEL_PIDS_STRING}" | wc -w)

  if [[ "${EXISTING_TUNNEL_PIDS_COUNT}" -gt 0 ]]; then
    >&2 echo "SSH tunnel/s between the source and the VM on port '${VM_PORT}' already exists with Process ID(s): ${EXISTING_TUNNEL_PIDS_STRING}"
    exit 1
  fi

  echo "No SSH tunnel found. Creating one."
}


function create_reverse_ssh_tunnel {
  echo "Setting up SSH tunnel between the source and the VM on port '${VM_PORT}'"

  gcloud compute ssh "${VM_NAME}" --zone="${VM_ZONE}" --project="${PROJECT_ID}" -- -f -N -R "${VM_PORT}:${SOURCE_DB_LOCAL_IP}:${SOURCE_DB_LOCAL_PORT}"

  if [[ "$?" -eq 0 ]]; then
    echo "SSH tunnel is ready on port ${VM_PORT}"
  fi
}


verify_connectivity_to_source_db
existing_instance
create_reverse_ssh_tunnel
