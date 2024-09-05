# -*- mode: ruby -*-
# vi: set ft=ruby :

VX_BOX = 'CumulusCommunity/cumulus-vx'

$cumulus_script = <<~SCRIPT
  echo "### RUNNING CUMULUS EXTRA CONFIG ###"
  source /etc/lsb-release
  echo "  INFO: Detected Cumulus Linux v$DISTRIB_RELEASE Release"

  echo "### Disabling default remap on Cumulus VX..."
  mv -v /etc/hw_init.d/S10rename_eth_swp.sh /etc/S10rename_eth_swp.sh.backup &> /dev/null

  echo "### Giving Vagrant User Ability to Run NCLU Commands ###"
  adduser vagrant netedit
  adduser vagrant netshow

  echo "### DONE ###"
SCRIPT
def configure_switches(config, _wbid, _offset)
  config.vm.define 'spine01' do |device|
    device.vm.box = VX_BOX
    device.vm.box_version = '4.2.0'
    device.vm.hostname = 'spine01'
    device.vm.synced_folder '.', '/vagrant', disabled: true

    device.vm.provider :libvirt do |v|
      v.memory = 768
      v.cpus = 2
      v.graphics_passwd = 'password'
    end

    swp1_mac = generate_mac_address(1, 1)
    swp2_mac = generate_mac_address(1, 2)
    swp3_mac = generate_mac_address(1, 3)
    swp4_mac = generate_mac_address(1, 4)

    device.vm.network :private_network, **create_tunnel('spine01', 'exit', swp1_mac, 'swp1')
    device.vm.network :private_network, **create_tunnel('spine01', 'leaf01', swp2_mac, 'swp2')
    device.vm.network :private_network, **create_tunnel('spine01', 'mikrotik', swp3_mac, 'swp3')
    device.vm.network :private_network, **create_tunnel('spine01', 'laptop', swp4_mac, 'swp4')

    device.vm.provision :shell, privileged: false, inline: 'echo "$(whoami)" > /tmp/normal_user'
    device.vm.provision :shell, inline: <<-DELETE_UDEV_DIRECTORY
      if [ -d "/etc/udev/rules.d/70-persistent-net.rules" ]; then
        rm -rfv /etc/udev/rules.d/70-persistent-net.rules &> /dev/null
      fi
      rm -rfv /etc/udev/rules.d/70-persistent-net.rules &> /dev/null
    DELETE_UDEV_DIRECTORY

    [swp1_mac, swp2_mac, swp3_mac, swp4_mac].each_with_index do |mac, idx|
      device.vm.provision :shell, inline: <<-UDEV_RULE
            echo "INFO: Adding UDEV Rule: #{mac} --> swp#{idx + 1}"
            echo 'ACTION=="add", SUBSYSTEM=="net", ATTR{address}=="#{mac}", NAME="swp#{idx + 1}", SUBSYSTEMS=="pci"' >> /etc/udev/rules.d/70-persistent-net.rules
      UDEV_RULE
    end

    device.vm.provision :shell, inline: $cumulus_script, reboot: true

    device.vm.provision :shell, inline: <<-NETWORK_COMMANDS
      echo "Running network commands..."
      net add int swp1,swp2,swp3,swp4
      net commit
      echo "Network commands executed successfully"
    NETWORK_COMMANDS

    device.vm.provision :shell, inline: <<-NETWORK_COMMANDS
      echo "Running network commands..."
      net add vlan 10
      net add int swp1,swp2,swp3,swp4 bridge access 10
      net commit
      echo "Network commands executed successfully"
    NETWORK_COMMANDS

    device.vm.provision :shell, inline: <<-NETWORK_COMMANDS
      echo "Running network commands..."
      net sh int
    NETWORK_COMMANDS
  end

  config.vm.define 'leaf01' do |device|
    device.vm.box = VX_BOX
    device.vm.box_version = '4.2.0'
    device.vm.hostname = 'leaf01'
    device.vm.synced_folder '.', '/vagrant', disabled: true

    device.vm.provider :libvirt do |v|
      v.memory = 768
      v.cpus = 2
      v.graphics_passwd = 'password'
      v.nic_adapter_count = 33
    end

    device.vm.provision :shell, privileged: false, inline: 'echo "$(whoami)" > /tmp/normal_user'
    device.vm.provision :shell, inline: <<-DELETE_UDEV_DIRECTORY
      if [ -d "/etc/udev/rules.d/70-persistent-net.rules" ]; then
        rm -rfv /etc/udev/rules.d/70-persistent-net.rules &> /dev/null
      fi
      rm -rfv /etc/udev/rules.d/70-persistent-net.rules &> /dev/null
    DELETE_UDEV_DIRECTORY


    # Create a list of devices that are attached to the leaf switch
    attached_devices = ['spine01']
    (0..(CONTROL_PLANE_COUNT-1)).each do |control_plane_idx|
      machine_base_name = "control-plane-#{control_plane_idx}"
      attached_devices << machine_base_name
    end
    (0..(COMPUTE_COUNT-1)).each do |compute_idx|
      machine_base_name = "compute-#{compute_idx}"
      attached_devices << machine_base_name
    end
    (0..(CEPH_HOT_COUNT-1)).each do |compute_idx|
      machine_base_name = "ceph-hot-#{compute_idx}"
      attached_devices << machine_base_name
    end
    (0..(CEPH_WARM_COUNT-1)).each do |compute_idx|
      machine_base_name = "ceph-warm-#{compute_idx}"
      attached_devices << machine_base_name
    end

    swp_list = []
    attached_devices.each_with_index do |device_name, idx|
      swp_name = "swp#{idx + 1}"
      swp_list << swp_name
      swp_mac = generate_mac_address(2, idx +1)
      device.vm.network :private_network, **create_tunnel('leaf01', device_name, swp_mac, swp_name)
      device.vm.provision :shell, inline: <<-UDEV_RULE
            echo "INFO: Adding UDEV Rule: #{swp_mac} --> #{swp_name} for #{device_name}"
            echo 'ACTION=="add", SUBSYSTEM=="net", ATTR{address}=="#{swp_mac}", NAME="#{swp_name}", SUBSYSTEMS=="pci"' >> /etc/udev/rules.d/70-persistent-net.rules
      UDEV_RULE
    end

    device.vm.provision :shell, inline: $cumulus_script, reboot: true

    device.vm.provision :shell, inline: <<-NETWORK_COMMANDS
      echo "Running network commands..."
      net add int #{swp_list.join(',')}
      net commit
      echo "Network commands executed successfully"
    NETWORK_COMMANDS

    device.vm.provision :shell, inline: <<-NETWORK_COMMANDS
      echo "Running network commands..."
      net add vlan 10
      net add int #{swp_list.join(',')} bridge access 10
      net commit
      echo "Network commands executed successfully"
    NETWORK_COMMANDS

    device.vm.provision :shell, inline: <<-NETWORK_COMMANDS
      echo "Running network commands..."
      net sh int
    NETWORK_COMMANDS
  end
end
