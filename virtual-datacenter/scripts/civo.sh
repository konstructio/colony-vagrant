#!/usr/bin/env bash

create_datacenter() {
  echo -e "${GREEN}Datacenter creation started${NOCOLOR}"
  civo instance create \
    --size g4s.2xlarge \
    --sshkey "${KUBEFIRST_TEAM_INFO}" \
    --diskimage ubuntu-jammy \
    --script ../../scripts/cloud-init \
    --initialuser root "colony-${KUBEFIRST_TEAM_INFO}" \
    --hostname "colony-${KUBEFIRST_TEAM_INFO}" \
    --wait \
    --output json
  echo -e "${GREEN}Datacenter created${NOCOLOR}"
}

wait_for_civo_status() {
  echo -e "${GREEN}Waiting for the instance to be active${NOCOLOR}"
  while true; do
    if check_civo_status; then
      break
    fi
    sleep 5
  done

  echo -e "${GREEN}Instance is active${NOCOLOR}"

  RETRIES=5
  SLEEP_INTERVAL=10

  for ((i = 1; i <= RETRIES; i++)); do
    echo "Attempting to connect (Attempt $i of $RETRIES)..."
    local sshCommand
    local fullCommand

    sshCommand=$(civo_get_ssh_command)
    fullCommand="$sshCommand -tt 'exit'"
    execute_command "$fullCommand" "autoApprove"

    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
      echo "SSH connection successful."
      check_cloud_init_status
      check_vagrant_status
      break
    else
      echo "Connection failed. Retrying in $SLEEP_INTERVAL seconds..."
      sleep $SLEEP_INTERVAL
    fi
  done

  if [ $i -gt $RETRIES ]; then
    echo "Failed to connect to $HOST after $RETRIES attempts."
    exit 1
  fi
}

check_civo_status() {
  local status
  status=$(civo instance show "colony-${KUBEFIRST_TEAM_INFO}" --fields status --output json | jq -r '.status' | tr -d '[:space:]')

  # Remove ANSI color codes if they exist
  # shellcheck disable=SC2001
  status=$(echo "$status" | sed 's/\x1b\[[0-9;]*m//g')

  if [ -z "$status" ]; then
    echo "Failed to obtain instance status"
    return 1
  fi

  echo "Status: $status"

  if echo "$status" | grep -q "^ACTIVE"; then
    echo "Instance is active"

    local ip
    ip=$(civo_get_public_ip)
    echo "Public IP: $ip"

    if [ -z "$ip" ]; then
      echo "Failed to obtain public IP: the system is not ready yet"
      return 1
    fi

    return 0
  else
    echo "Instance is not active"
    return 1
  fi
}

create_ssh_key() {
  echo -e "${GREEN}Creating SSH key${NOCOLOR}"

  if civo sshkey find "${KUBEFIRST_TEAM_INFO}"; then
    civo sshkey create "${KUBEFIRST_TEAM_INFO}" --key "$SELECTED_KEY"
    echo -e "${GREEN}SSH key created${NOCOLOR}"
  fi
}

civo_ssh_command() {
  echo -e "${GREEN}Getting the SSH command${NOCOLOR}"
  command=$(civo_get_ssh_command)
  execute_command "$command" "autoApprove"
}

civo_get_ssh_command() {
  ip=$(civo instance show "colony-${KUBEFIRST_TEAM_INFO}" --fields public_ip --output json | jq -r '.public_ip')
  local keyName
  # shellcheck disable=SC2001
  keyName=$(echo "$SELECTED_KEY" | sed 's/\.pub//')
  echo "ssh -o StrictHostKeyChecking=no -i $keyName root@$ip"
}

civo_get_public_ip() {
  ip=$(civo instance show "colony-${KUBEFIRST_TEAM_INFO}" --fields public_ip --output json | jq -r '.public_ip')
  echo "$ip"
}

civo_destroy() {
  echo -e "${GREEN}Destroying the instance${NOCOLOR}"
  command="civo instance remove colony-${KUBEFIRST_TEAM_INFO} -y"
  execute_command "$command"
}
