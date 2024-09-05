# -*- mode: ruby -*-
# vi: set ft=ruby :

ALPINE_BOX = 'generic/alpine319'

$alpine_script = <<~SCRIPT

  echo "Adding community repository..."
  echo "http://dl-cdn.alpinelinux.org/alpine/v3.8/community" >> /etc/apk/repositories
  apk update

  echo "Installing lldpd..."
  apk add lldpd

  echo "Enabling and starting lldpd service..."
  rc-update add lldpd
  rc-service lldpd start
SCRIPT

def configure_servers(config, _wbd, _offset)
  config.vm.define 'exit' do |device|
    device.vm.box = ALPINE_BOX
    device.vm.hostname = 'exit'

    device.vm.provider :libvirt do |v|
      v.memory = 1024
      v.cpus = 1
      v.graphics_passwd = 'password'
    end

    # link for eth1 --> spine01:swp1
    device.vm.network 'private_network', **create_tunnel('exit', 'spine01', generate_mac_address(3, 1), 'eth1')

    device.vm.provision :shell, inline: $alpine_script
    device.vm.provision :shell, inline: <<-SHELL
      echo "Installing iptables..."
      apk add iptables

      echo "Configuring traffic forwarding and iptables rules..."
      echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
      sysctl -p /etc/sysctl.conf

      iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
      iptables-save > /etc/iptables/rules.v4

      echo "Persisting iptables rules on reboot..."
      echo "#!/bin/sh" >> /etc/network/if-pre-up.d/iptables
      echo "iptables-restore < /etc/iptables/rules.v4" >> /etc/network/if-pre-up.d/iptables
      chmod +x /etc/network/if-pre-up.d/iptables

      echo "Configuring IP address on eth1..."
      ip addr add 10.0.10.1/24 dev eth1
      ip link set up eth1

      echo "Configuring lldpd..."
      echo 'DAEMON_ARGS="-S 2c:60:0c:ad:d5:01 -I eth1 -L db:16:f0:5b:28:80"' > /etc/conf.d/lldpd
    SHELL
  end

  (0..(CONTROL_PLANE_COUNT-1)).each do |control_plane_idx|
    machine_base_name = "control-plane-#{control_plane_idx}"
    
    config.vm.define machine_base_name do |device|
      device.vm.hostname = machine_base_name
      device.vm.boot_timeout = 30
      device.vm.synced_folder ".", "/vagrant", disabled: true

      device.vm.provider :libvirt do |v|
        v.storage :file, size: '10G'
        v.memory = 2048
        v.cpus = 1
        v.graphics_passwd = 'password'
        v.boot "hd"
        v.boot "network"
      end

      network_args = create_tunnel(machine_base_name, 'leaf01', generate_mac_address(4, 1), 'eth1')
      network_args.merge!(libvirt__network_name: 'data')
      device.vm.network 'private_network', **network_args

      # hook after up to register the vm with vbmc
      device.trigger.after :provision do |trigger|
        # register_vbmc_server(machine_base_name)
      end

      # hook after destroy to remove the vm from vbmc
      device.trigger.after :destroy do |trigger|
        # This is not to be used, as this is called when the VM is simply shutdown
        # With ipmi, this will not allow us to restart it after it is shutdown
        # remove_vbmc_server(machine_base_name)
      end

    end
  end

  (0..(COMPUTE_COUNT-1)).each do |compute_idx|
    machine_base_name = "compute-#{compute_idx}"

    config.vm.define machine_base_name do |device|
      device.vm.hostname = machine_base_name

      device.vm.provider :libvirt do |v|
        v.memory = 2048
        v.cpus = 1
        v.graphics_passwd = 'password'
        v.boot "hd"
        v.boot "network"

        (1..2).each do |nvme_idx|
          attach_nvme_disk(v, $vagrant_root + "nvme_disk-#{machine_base_name}-#{nvme_idx}.img", "NVMEworker-#{nvme_idx}")
        end
      end

      (1..2).each do |nvme_idx|
        device.trigger.before :up do |trigger|
          trigger.ruby do |_env, _machine|
            recreate_attached_disk($vagrant_root + "nvme_disk-#{machine_base_name}-#{nvme_idx}.img", 10)
          end
        end
      end

      # link for eth1 --> leaf01:swp2
      network_args = create_tunnel(machine_base_name, 'leaf01', generate_mac_address(4, 1), 'eth1')
      network_args.merge!(libvirt__network_name: 'data')
      device.vm.network 'private_network', **network_args
    end
  end

  if CEPH_HOT_COUNT > 0
    (0..(CEPH_HOT_COUNT-1)).each do |compute_idx|
      machine_base_name = "ceph-hot-#{compute_idx}"

      config.vm.define machine_base_name do |device|
        device.vm.box = ALPINE_BOX
        device.vm.hostname = machine_base_name

        device.vm.provider :libvirt do |v|
          v.memory = 1024
          v.cpus = 1
          v.graphics_passwd = 'password'

          # Set pxe network NIC as default boot
          # boot_network = { 'network' => 'data' }
          # v.boot boot_network
          # v.boot 'hd'

          (1..4).each do |nvme_idx|
            attach_nvme_disk(v, $vagrant_root + "nvme_disk-#{machine_base_name}-#{nvme_idx}.img", "NVMEworker-#{nvme_idx}")
          end
        end

        (1..4).each do |nvme_idx|
          device.trigger.before :up do |trigger|
            trigger.ruby do |_env, _machine|
              recreate_attached_disk($vagrant_root + "nvme_disk-#{machine_base_name}-#{nvme_idx}.img", 10)
            end
          end
        end

        # link for eth1 --> leaf01:swp2
        network_args = create_tunnel(machine_base_name, 'leaf01', generate_mac_address(4, 1), 'eth1')
        network_args.merge!(libvirt__network_name: 'data')
        device.vm.network 'private_network', **network_args

        device.vm.provision :shell, inline: $alpine_script
        device.vm.provision :shell, inline: <<-SHELL
          echo "Configuring IP address on eth1..."
          ip addr add #{next_static_ip(LOCAL_SUBNET_RANGE)} dev eth1
          ip link set up eth1

          echo "Configuring default route via exit node..."
          ip route del default
          ip route add default via 10.0.10.1 dev eth1
        SHELL

        device.vm.provision :shell, inline: <<-SHELL
          echo "Configuring lldpd..."
          echo 'DAEMON_ARGS="-S 2c:60:0c:ad:d5:02 -I eth1 -L db:16:f0:5b:28:81"' > /etc/conf.d/lldpd
        SHELL
      end
    end
  end

  if CEPH_WARM_COUNT > 0
    (0..(CEPH_WARM_COUNT-1)).each do |compute_idx|
      machine_base_name = "ceph-warm-#{compute_idx}"

      config.vm.define machine_base_name do |device|
        device.vm.box = ALPINE_BOX
        device.vm.hostname = machine_base_name

        device.vm.provider :libvirt do |v|
          v.memory = 1024
          v.cpus = 1
          v.graphics_passwd = 'password'

          # Set pxe network NIC as default boot
          # boot_network = { 'network' => 'data' }
          # v.boot boot_network
          # v.boot 'hd'

          (1..4).each do |ssd_idx|
            v.storage :file, size: '10G'
          end
        end

        # link for eth1 --> leaf01:swp2
        network_args = create_tunnel(machine_base_name, 'leaf01', generate_mac_address(4, 1), 'eth1')
        network_args.merge!(libvirt__network_name: 'data')
        device.vm.network 'private_network', **network_args

        device.vm.provision :shell, inline: $alpine_script
        device.vm.provision :shell, inline: <<-SHELL
          echo "Configuring IP address on eth1..."
          ip addr add #{next_static_ip(LOCAL_SUBNET_RANGE)} dev eth1
          ip link set up eth1

          echo "Configuring default route via exit node..."
          ip route del default
          ip route add default via 10.0.10.1 dev eth1
        SHELL

        device.vm.provision :shell, inline: <<-SHELL
          echo "Configuring lldpd..."
          echo 'DAEMON_ARGS="-S 2c:60:0c:ad:d5:02 -I eth1 -L db:16:f0:5b:28:81"' > /etc/conf.d/lldpd
        SHELL
      end
    end
  end
end