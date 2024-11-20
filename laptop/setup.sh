#!/bin/bash

install_docker() {
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	add-apt-repository "deb https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
	update_apt
	apt-get install --no-install-recommends containerd.io docker-ce docker-ce-cli dnsmasq
	gpasswd -a vagrant docker
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

kubectl_for_vagrant_user() {
	runuser -l vagrant -c "mkdir -p ~/.kube/"
	runuser -l vagrant -c "k3d kubeconfig get -a > ~/.kube/config"
	chmod 600 /home/vagrant/.kube/config
	echo 'export KUBECONFIG="/home/vagrant/.colony/kubeconfig"' >> /home/vagrant/.bashrc
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

install_colony() {
	# local colony_version=$1

	wget https://objectstore.nyc1.civo.com/konstruct-assets/colony/v0.2.0-rc4/colony_Linux_x86_64.tar.gz
	tar xvf colony_Linux_x86_64.tar.gz
	sudo mv colony /usr/local/bin
	colony version
}

main() {
	local kubectl_version="1.28.3"

	update_apt
	install_docker
	configure_dnsmasq
	# https://github.com/ipxe/ipxe/pull/863
	# Needed after iPXE increased the default TCP window size to 2MB.
	sudo ethtool -K eth1 tx off sg off tso off
	install_kubectl "$kubectl_version"
	install_colony
	kubectl_for_vagrant_user
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	set -euxo pipefail

	main "$@"
	echo loadbalancer_ip="$1"
	echo "all done!"
fi
