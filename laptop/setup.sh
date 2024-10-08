#!/bin/bash

install_docker() {
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	add-apt-repository "deb https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
	update_apt
	apt-get install --no-install-recommends containerd.io docker-ce docker-ce-cli dnsmasq
	gpasswd -a vagrant docker
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
	sed -i 's/127.0.0.1/localhost/g' ~/.kube/config
	export KUBECONFIG=~/.kube/config
	cat ~/.kube/config

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

kubectl_for_vagrant_user() {
	echo "**********************************"
	runuser -l vagrant -c "mkdir -p /home/vagrant/.kube"
	cp ./kubeconfig.yaml /home/vagrant/.kube/config
	chown vagrant:vagrant /home/vagrant/.kube/config

	chmod 600 /home/vagrant/.kube/config
	echo 'export KUBECONFIG="/home/vagrant/.kube/config"' >> /home/vagrant/.bashrc
	echo "**********************************"
}

helm_install_tink_stack() {
	local namespace=$1
	local version=$2
	local interface=$3
	local loadbalancer_ip=$4

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
		--values manifests/proxy-values.yaml \
		--set "stack.loadBalancerIP=${loadbalancer_ip}" \
		--set "smee.publicIP=${loadbalancer_ip}"
}

configure_dnsmasq() {
	cat <<-EOF >/etc/dnsmasq.conf
		dhcp-range=10.0.10.100,10.0.10.200,255.255.255.0,12h
		#dhcp-option=option:router,172.31.0.1
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
	local namespace="tink-system"

	start_k3s "$k3s_version"
	install_helm
	kubectl get all --all-namespaces
	kubectl_for_vagrant_user
	helm_install_tink_stack "$namespace" "$helm_chart_version" "$loadbalancer_interface" "$loadbalancer_ip"
	apply_manifests "$manifests_dir" "$namespace"
}

main() {
	local loadbalancer_ip="$1"
	local manifests_dir="$2"
	# https://github.com/tinkerbell/charts/pkgs/container/charts%2Fstack
	local helm_chart_version="0.4.4"
	local loadbalancer_interface="eth1"
	local kubectl_version="1.28.3"
	local k3s_version="v1.30.2-k3s1"

	update_apt
	install_docker
	configure_dnsmasq
	# https://github.com/ipxe/ipxe/pull/863
	# Needed after iPXE increased the default TCP window size to 2MB.
	sudo ethtool -K eth1 tx off sg off tso off
	install_kubectl "$kubectl_version"
	run_helm "$manifests_dir" "$loadbalancer_ip" "$helm_chart_version" "$loadbalancer_interface" "$k3s_version"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	set -euxo pipefail

	main "$@"
	echo loadbalancer_ip="$1"
	echo "all done!"
fi