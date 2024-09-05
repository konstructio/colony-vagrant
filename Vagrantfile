# -*- mode: ruby -*-
# vi: set ft=ruby :

require_relative 'switches'
require_relative 'servers'
require_relative 'helpers'


# Set the number of server to configure
CONTROL_PLANE_COUNT = 3

# Set the number of server to configure
COMPUTE_COUNT = 3

# Ceph Hot
CEPH_HOT_COUNT = 0

# Ceph Warm
CEPH_WARM_COUNT = 0

# Init the subnet cache and load it with the first IP
LOCAL_SUBNET_RANGE = '10.0.10.0/24'
# we always want the exit node to have .1 in the range. we preload the
# next_static_ip function with .1
next_static_ip(LOCAL_SUBNET_RANGE)

# reserve ip for loadbalancer
ipForLBWithMask = next_static_ip(LOCAL_SUBNET_RANGE)
ipForLB = ipForLBWithMask.split("/")[0]

REQUIRED_PLUGINS_LIBVIRT = %w[vagrant-libvirt].freeze
exit unless REQUIRED_PLUGINS_LIBVIRT.all? do |plugin|
  Vagrant.has_plugin?(plugin) || (
    puts "The #{plugin} plugin is required. Please install it with:"
    puts "$ vagrant plugin install #{plugin}"
    false
  )
end

Vagrant.configure('2') do |config|
  config.ssh.forward_agent = true

  wbid = 1
  offset = wbid * 100

  config.vm.provider :libvirt do |libvirt|
    libvirt.management_network_address = "10.255.#{wbid}.0/24"
    libvirt.management_network_name = "wbr#{wbid}"
    libvirt.default_prefix = ''
  end

  # Create switches
  configure_switches(config, wbid, offset)

  # Create servers
  configure_servers(config, wbid, offset)

  config.vm.define "laptop" do |laptop|
    laptop.vm.box = "generic/ubuntu2204"
    laptop.vm.network :private_network, **create_tunnel('laptop', 'spine01', generate_mac_address(6,1), 'eth2')

    laptop.vm.provider "libvirt" do |l, override|
      l.memory = 2048
      l.cpus = 2
      l.graphics_passwd = "password"

      override.vm.synced_folder "laptop", "/home/vagrant/manifests", type: "rsync"
    end
    ipWithMask = next_static_ip(LOCAL_SUBNET_RANGE)
    ip = ipWithMask.split("/")[0]

    laptop.vm.provision :shell, inline: <<-SHELL
      echo "Configuring IP address on eth1..."
      ip addr add #{ipWithMask} dev eth1
      ip link set up eth1
      ip a sh dev eth1
      
      ip route del default
      ip route add default via 10.0.10.1 dev eth1
      ip route
      echo "successfully configured IP address on eth1"
    SHELL

    laptop.vm.provision :shell, path: "laptop/setup.sh", args: [ipForLB, "/home/vagrant/manifests"]
  end

  if false 
    config.vm.define 'mikrotik' do |device|
      device.vm.box = 'mikrotik/chr'

      device.vm.network 'private_network', **create_tunnel('mikrotik', 'spine01', generate_mac_address(5, 1), 'ether2')

      device.trigger.after :up do |trigger|
        trigger.run = {inline: "bash -c 'vagrant ssh mikrotik -- /interface/print'"}
      end

      device.trigger.after :up do |trigger|
        trigger.run = {inline: "bash -c 'vagrant ssh mikrotik -- /ip/address/add address=10.0.10.3/24 interface=ether2'"}
      end
    end
  end
end
