#!/usr/bin/env bash

execute_command() {
  local command=$1
  local autoApprove=$2

  echo -e "${YELLOW}$command ${NOCOLOR}"

  if [ -n "$autoApprove" ]; then
    if [ -n "$command" ]; then
      eval "$command"
    fi
  else
    if [ -n "$command" ]; then
      echo -e "${BLUE}Do you want to execute the command?${NOCOLOR}"
      choice=$(gum choose "Yes" "No")
      if [ "$choice" = "Yes" ]; then
        eval "$command"
      fi
    fi
  fi
}

ask_skip_data_collection() {
  echo -e "${GREEN}Do you want to skip filling in data? (yes/no)${NOCOLOR}"
  trap "echo 'Script terminado por el usuario'; exit 1" TSTP
  local response
  response=$(choose_option "yes" "yes" "no")
  if [[ "$response" == "no" ]]; then
    return 1
  else
    return 0
  fi
}

setup_vagrant() {
  local vagrantCommand="echo \\\"alias k=kubectl\\\" >> ~/.bashrc; \
echo \\\"export COLONY_API_KEY=$COLONY_API_KEY\\\" >> ~/.bashrc; \
source ~/.bashrc; \
until systemctl is-active --quiet snapd.service; do sleep 1; done; \
echo 'snapd.service is active and working.'; \
until [ \\\"\\\$(snap changes | grep -e \\\"Done.*Initialize system state\\\" | wc -l)\\\" -gt 0 ]; do echo 'Waiting for snapd to be ready...'; sleep 5; done; \
echo 'snapd is ready.'; \
sudo snap install --classic kubectx; \
kubens tink-system; \
sudo kubectl -n tink-system create secret generic laptop-kubeconfig --from-file=kubeconfig=\$HOME/.kube/config; \
curl -sLO https://github.com/konstructio/colony/releases/download/${COLONY_CLI_VERSION}/colony_Linux_x86_64.tar.gz && tar -xvf colony_Linux_x86_64.tar.gz; \
export COLONY_API_KEY=$COLONY_API_KEY; \
sudo install -m 0755 ./colony /usr/local/bin/; \
sudo kubectl -n tink-system get secret laptop-kubeconfig; \
/home/vagrant/manifests/helm-upgrade.sh /home/vagrant/manifests/proxy-values.yaml; \
echo '------------------------------------'; \
echo 'kubens tink-system'; \
echo 'kubens tink-system' >> ~/.bashrc; \
echo 'watch kubectl get pods'; \
echo 'kubectl get wf,tpl,hw'; \
echo 'watch kubectl get workflow'; \
echo '------------------------------------'; \
"

  local sshCommand
  sshCommand=$(civo_get_ssh_command)

  echo -e "${YELLOW}$sshCommand ${NOCOLOR}"

  local fullCommand="$sshCommand -tt 'export GITHUB_USER=\"$GITHUB_USER\"; \
export GITHUB_TOKEN=\"$GITHUB_TOKEN\"; \
vagrant plugin list | grep -q vagrant-libvirt || vagrant plugin install vagrant-libvirt; \
curl -sLO https://github.com/konstructio/colony/releases/download/${COLONY_CLI_VERSION}/colony_Linux_x86_64.tar.gz && tar -xvf colony_Linux_x86_64.tar.gz; \
sudo install -m 0755 ./colony /usr/local/bin/; \
sudo systemctl restart libvirtd; \
git clone git@github.com:konstructio/colony-vagrant.git colony-vagrant; \
cd colony-vagrant; vagrant up spine01 leaf01 exit laptop; vagrant ssh laptop -c \"$vagrantCommand\"; \
vagrant ssh laptop; exec /bin/bash -i'"

  execute_command "$fullCommand" "autoApprove"
}

access_ssh() {
  local command
  command=$(civo_get_ssh_command)
  execute_command "$command"
}

access_ssh_laptop() {
  local command
  command=$(civo_get_ssh_command)
  command="$command -tt 'cd colony/vagrant-dc; vagrant ssh laptop; exec /bin/bash -i'"
  execute_command "$command"
}

delete_laptop() {
  local command
  command=$(civo_get_ssh_command)
  echo -e "${YELLOW}Please delete all records related with this laptop, after to destroy this one.${NOCOLOR}"
  command="$command -tt 'cd colony/vagrant-dc; vagrant destroy laptop -f; exit;'"
  execute_command "$command"
}

get_ssh_config() {
  local publicIp
  publicIp=$(civo_get_public_ip)
  echo -e "${YELLOW}Copying the private key from laptop to your local machine${NOCOLOR}"
  echo -e "${YELLOW} $publicIp ${NOCOLOR}"
  scp "root@$publicIp:/root/colony/vagrant-dc/.vagrant/machines/laptop/libvirt/private_key" ~/private_key_laptop
  chmod 600 ~/private_key_laptop
  echo -e "${GREEN}The private key has been copied to your local machine ~/private_key_laptop${NOCOLOR}"

  # get ip of laptop inside the vagrant network
  local command
  command=$(civo_get_ssh_command)
  echo -e "${YELLOW}Getting IP from laptop.${NOCOLOR}"

  local laptopIP
  laptopIP=$(ssh -i ~/.ssh/id_ed25519 "root@${publicIp}" -tt "cd colony/vagrant-dc; vagrant ssh laptop -c 'hostname -I | awk \"{print \\\$1}\"'")

  echo -e "${GREEN}The IP of laptop is $laptopIP${NOCOLOR}"

  update_ssh_config "$publicIp" "$laptopIP"
}

update_ssh_config() {
  local publicIp=$1
  local laptopIP=$2
  local ssh_config_file=~/.ssh/config

  mkdir -p ~/.ssh

  local tmp_file
  tmp_file=$(mktemp)

  awk '
    BEGIN {in_civo_colony=0; in_colony_laptop=0}
    /^Host Civo-colony-VM/ {in_civo_colony=1; next}
    /^Host colony-laptop/ {in_colony_laptop=1; next}
    /^Host / {in_civo_colony=0; in_colony_laptop=0}
    !in_civo_colony && !in_colony_laptop {print}
  ' "$ssh_config_file" >"$tmp_file"

  {
    echo ""
    echo "Host Civo-colony-VM"
    echo "  HostName $publicIp"
    echo "  User root"
    echo "  ForwardAgent yes"
    echo ""
    echo "Host colony-laptop"
    echo "  Hostname $laptopIP"
    echo "  ProxyJump Civo-colony-VM"
    echo "  User vagrant"
    echo "  ForwardAgent yes"
    echo "  IdentityFile ~/private_key_laptop"
  } >>"$tmp_file"

  mv "$tmp_file" "$ssh_config_file"

  echo "SSH config file updated at $ssh_config_file"
}

check_vagrant_status() {
  echo "Checking Vagrant status..."
  local sshCommand
  sshCommand=$(civo_get_ssh_command)

  # Loop until Vagrant is installed and running
  while true; do
    $sshCommand -o BatchMode=yes -tt "command -v vagrant >/dev/null 2>&1 && vagrant global-status"
    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
      echo "Vagrant is running."
      break
    else
      echo "Vagrant is not running or not installed yet. Retrying in 10 seconds..."
      sleep 10
    fi
  done
}

check_cloud_init_status() {
  echo "Checking cloud-init status..."
  local sshCommand
  sshCommand=$(civo_get_ssh_command)

  # Loop until cloud-init is finished
  while true; do
    $sshCommand -o BatchMode=yes -tt "sudo cloud-init status --wait"
    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
      echo "Cloud-init is finished."
      break
    else
      echo "Cloud-init is not finished yet. Retrying in 10 seconds..."
      sleep 10
    fi
  done
}

unblock_local_ssh() {
  echo -e "${YELLOW}Unblocking local SSH${NOCOLOR}"
  eval "$(ssh-agent -s)"
  local selectedKeyPrivate
  # shellcheck disable=SC2001
  selectedKeyPrivate=$(echo "$SELECTED_KEY" | sed 's/\.pub//')
  ssh-add "$selectedKeyPrivate"
}
