#!/bin/bash

prepare_system() {
  apt update
  apt install curl gnupg lsb-release software-properties-common -y
  apt install iproute2 -y
  apt install ethtool -y

  if ! command -v sudo &>/dev/null; then
    apt install sudo -y
  fi
}

disable_network_offloads() {
  local interface=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n 1)
  if [[ -n "$interface" ]]; then
    echo "Disabling tx, sg, tso off for interface $interface"
    sudo ethtool -K "$interface" tx off sg off tso off
  else
    echo "No active network interface found."
    exit 1
  fi
}

install_docker() {
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	add-apt-repository "deb https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
	update_apt
	apt-get install --no-install-recommends containerd.io docker-ce docker-ce-cli dnsmasq
	gpasswd -a "$1" docker
}

install_kubectx_kubens() {
	update_apt
	apt-get install --no-install-recommends kubectx
}

install_kubectl() {
	local kubectl_version=$1

	curl -LO https://dl.k8s.io/v"$kubectl_version"/bin/linux/amd64/kubectl
	chmod +x ./kubectl
	mv ./kubectl /usr/local/bin/kubectl
}

install_helm() {
	helm_ver=v3.9.4

	curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
	chmod 700 get_helm.sh
	./get_helm.sh --version "$helm_ver"
}

apt-get() {
	DEBIAN_FRONTEND=noninteractive command apt-get \
		--allow-change-held-packages \
		--allow-downgrades \
		--allow-remove-essential \
		--allow-unauthenticated \
		--option Dpkg::Options::=--force-confdef \
		--option Dpkg::Options::=--force-confold \
		--yes \
		"$@"
}

update_apt() {
	apt-get update
}

start_k3s() {
	local k3s_version=$1
	echo "Creating the cluster..."

	docker run -d --privileged --name ctrlplane-laptop \
		-e K3S_KUBECONFIG_OUTPUT=/output/kubeconfig.yaml \
		-e K3S_KUBECONFIG_MODE=666 \
		-v "$(pwd):/output" \
		-v k3s-server:/var/lib/rancher/k3s \
		--tmpfs=/run --tmpfs=/var/run \
		--network=host \
		rancher/k3s:"$k3s_version" server \
		--disable=traefik,servicelb \
		--tls-san=ctrlplane-laptop \
		--node-label="colony.konstruct.io/node-type=laptop"

	echo "Waiting for the cluster to be fully operational..."
	sleep 30

	echo "Configuring kubeconfig..."
	mkdir -p ~/.kube/

	cp ./kubeconfig.yaml ~/.kube/config || echo "Failed to get kubeconfig"
	export KUBECONFIG=~/.kube/config

	if [ -f ./kubeconfig.yaml ]; then
    cp ./kubeconfig.yaml ~/.kube/config
	else
    echo "Failed to get kubeconfig: kubeconfig.yaml not found"
    exit 1
	fi

	echo "Checking nodes..."
	until kubectl wait --for=condition=Ready nodes --all --timeout=600s; do
		echo "Waiting for nodes to be ready..."
		sleep 5
	done

	echo "Generating join token and storing it in a secret..."
	# docker exec -i ctrlplane-laptop k3s token create --print-join-command > token.txt (incompatible)
	docker exec -i ctrlplane-laptop cat /var/lib/rancher/k3s/server/node-token > token.txt
	kubectl create secret -n kube-system generic k3s-join-token --from-file=token.txt
}

kubectl_for_user() {
	local user=$1
	echo "**********************************"
	runuser -l "$user" -c "mkdir -p /home/$user/.kube"
	cp ./kubeconfig.yaml /home/"$user"/.kube/config
	chown "$user":"$user" /home/"$user"/.kube/config

	chmod 600 /home/"$user"/.kube/config
	echo 'export KUBECONFIG="/home/'"$user"'/.kube/config"' >> /home/"$user"/.bashrc
	echo "**********************************"
}

helm_install_tink_stack() {
	local namespace=$1
	local version=$2
	local interface=$3
	local loadbalancer_ip=$4
	local manifests_dir=$5

	trusted_proxies=""
	until [ "$trusted_proxies" != "" ]; do
		trusted_proxies=$(kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}' | tr ' ' ',')
	done
	helm install tink-stack oci://ghcr.io/tinkerbell/charts/stack \
		--version "$version" \
		--create-namespace \
		--namespace "$namespace" \
		--wait \
		--set "smee.trustedProxies=${trusted_proxies}" \
		--set "hegel.trustedProxies=${trusted_proxies}" \
		--set "stack.kubevip.interface=${interface}" \
		--values ${manifests_dir}/proxy-values.yaml \
		--set "stack.loadBalancerIP=${loadbalancer_ip}" \
		--set "smee.publicIP=${loadbalancer_ip}"
}

configure_dnsmasq() {
	cat <<-EOF >/etc/dnsmasq.conf
		dhcp-range=10.0.10.100,10.0.10.200,255.255.255.0,12h
		dhcp-option=option:router,10.0.10.1
		dhcp-option=option:dns-server,1.1.1.1
		dhcp-authoritative
		interface=eth1
		port=0
	EOF
	systemctl restart dnsmasq
}

apply_manifests() {
	local manifests_dir=$1
	local namespace=$2

	kubectl apply -n "$namespace" -f "$manifests_dir"/ubuntu-download.yaml
}

run_helm() {
	local manifests_dir=$1
	local loadbalancer_ip=$2
	local helm_chart_version=$3
	local loadbalancer_interface=$4
	local k3s_version=$5
	local user=$6
	local namespace="tink-system"

	start_k3s "$k3s_version"
	install_helm
	kubectl get all --all-namespaces
	kubectl_for_user "$user"
	helm_install_tink_stack "$namespace" "$helm_chart_version" "$loadbalancer_interface" "$loadbalancer_ip" "$manifests_dir"
	apply_manifests "$manifests_dir" "$namespace"
}

main() {
	local loadbalancer_ip="$1"
	local manifests_dir="$2"
	local is_physical="$3"
	# https://github.com/tinkerbell/charts/pkgs/container/charts%2Fstack
	local helm_chart_version="0.4.4"
	local kubectl_version="1.28.3"
	local k3s_version="v1.30.2-k3s1"

  local loadbalancer_interface="eth1"
  if [[ -n "$4" ]]; then
    loadbalancer_interface="$4"
  fi

	update_apt
	prepare_system
	# disable_network_offloads

	local user="vagrant"
	if [[ "$is_physical" == "true" ]]; then
		user=$(whoami)
	fi

	install_docker "$user"
	# configure_dnsmasq
	# sudo ethtool -K eth1 tx off sg off tso off
	install_kubectl "$kubectl_version"
	run_helm "$manifests_dir" "$loadbalancer_ip" "$helm_chart_version" "$loadbalancer_interface" "$k3s_version" "$user"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	set -euxo pipefail

	main "$@"
	echo loadbalancer_ip="$1"
	echo "all done!"
fi

# kubectl config set-context --current --namespace=tink-system
# alias k='kubectl'

# INTERFACE: nsenter -t1 -n ip route | awk '/default/ {print $5}' | head -n1
# IP_LOAD_BALANCER: nsenter -t1 -n ip -4 addr show <INTERFACE> | awk '/inet / {print $2}' | cut -d/ -f1

#             loadBalancerIP     | folder_manifests | is_physical | loadbalancer_interface
# ./setup.sh "<IP_LOAD_BALANCER>"        "."             true         <INTERFACE>
# ./setup.sh "192.168.1.5" "." true enp1s0
