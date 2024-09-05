# vagrant_root is the path to the libvirt images directory
$vagrant_root = "/var/lib/libvirt/images/"
# tunnels is a global hash that stores the tunnel configuration between devices
$tunnels = {}
# udp_port is the starting port for the tunnels
$udp_port = 8000

# generate_mac_address generates a MAC address based on the node_id and
# interface_id the MAC address is in the format 52:54:00:xx:xx:xx with the last
# octet being random
def generate_mac_address(node_id, interface_id)
  "52:54:00:#{node_id.to_s(16).rjust(2, '0')}:#{interface_id.to_s(16).rjust(2, '0')}:#{rand(0x00..0xff).to_s(16).rjust(2, '0')}"
end

# create_tunnel creates a tunnel between two devices. If a tunnel already exists
# between the two devices, it will return the existing tunnel. If a tunnel exists
# in the reverse direction, it will return the existing tunnel with the ports swapped.
#
# e.g. create_tunnel('device1', 'device2', '00:00:00:00:00:01', 'eth0')
#      create_tunnel('device2', 'device1', '00:00:00:00:00:02', 'eth0')
#
def create_tunnel(device1, device2, device_mac, device_iface)
  key = "#{device1}-#{device2}"
  reverse_key = "#{device2}-#{device1}"

  if $tunnels.key?(key)
    # Tunnel already exists, return the existing tunnel with swapped ports
    tunnel = $tunnels[key]
  elsif $tunnels.key?(reverse_key)
    # Reverse tunnel exists, return the existing tunnel
    tunnel = $tunnels[reverse_key]
  else
    # Create a new tunnel
    local_port = $udp_port
    remote_port = $udp_port + 1
    $udp_port += 2

    tunnel = { local_port: local_port, remote_port: remote_port }

    # Store the tunnel in both directions
    $tunnels[key] = tunnel
    $tunnels[reverse_key] = { local_port: remote_port, remote_port: local_port }
  end

  return {
    mac:                        device_mac,
    libvirt__tunnel_type:       'udp',
    libvirt__iface_name:        device_iface,
    libvirt__tunnel_local_port: tunnel[:local_port],
    libvirt__tunnel_port:       tunnel[:remote_port],
    auto_config:                false
  }
end

# recreate_attached_disk deletes the existing disk image and recreates it with
# the specified size
def recreate_attached_disk(imageNameWithPath, diskSizeGB)
  if File.exist?(imageNameWithPath)
    system("sudo rm #{imageNameWithPath}")
  end
  system("sudo qemu-img create -f qcow2 #{imageNameWithPath} #{diskSizeGB}G")
  system("sudo chown libvirt-qemu:kvm #{imageNameWithPath}")
  system("sudo chmod 600 #{imageNameWithPath}")
  system("restorecon #{imageNameWithPath}")
end

# attach_nvme_disk attaches an NVMe disk to a device
def attach_nvme_disk(device, imageNameWithPath, diskID)
  device.qemuargs value: '-drive'
  device.qemuargs value: "file=#{imageNameWithPath},if=none,id=#{diskID}"
  device.qemuargs value: '-device'
  device.qemuargs value: "nvme,drive=#{diskID},serial=#{diskID}"
end

$subnet_cache = {}

# next_static_ip will return the next IP address in the given subnet. It
# tracks the subnets given and will return the next IP address in the range.
# The broadcast and network addresses are excluded from the range.
# e.g. 
#  next_static_ip('192.168.0.0/24') => '192.68.0.1'
#  next_static_ip('192.168.0.0/24') => '192.68.0.2'
def next_static_ip(subnet)
  # check if subnet already exists in the global cache
  if $subnet_cache.key?(subnet)
    ip = $subnet_cache[subnet]
    $subnet_cache[subnet] += 1
  else
    # init the subnet cache and return the .1 address
    $subnet_cache[subnet] = 2
    ip = 1
  end

  # parse the subnet
  ip_addr = IPAddr.new(subnet)
  # get the ip'th address in the subnet
  ip_addr.to_range.to_a[ip].to_s

  mask = subnet.split('/')[1]

  return "#{ip_addr.to_range.to_a[ip]}/#{mask}"
end

# register_vbmc_server will register the server with the next available
# port with vbmc and start the server
def register_vbmc_server(server_name)
  # list the servers
  servers = list_vbmc_servers

  found = false
  # loop through servers and see if there is a match on the "Domain name" key
  for server in servers
    return if server["Domain name"] == server_name
  end

  # get the next available port
  maxFoundPort = 16000
  for server in servers
    port = server["Port"]
    if port > maxFoundPort
      maxFoundPort = port
    end
  end

  # list servers from virsh
  found = false
  virsh_servers = `virsh list --all --name`
  for virsh_server in virsh_servers.split("\n")
    if virsh_server == server_name
      found = true
      break
    end
  end
  return if !found


  # create the server
  `vbmc add #{server_name} --port #{maxFoundPort + 1} --username admin --password password`
  `vbmc start #{server_name}`
end

# remove_vmbc_server will remove the given server from vbmc. It will do a
# vbmc list to get the list of servers and then remove the server if 
# it exists
def remove_vbmc_server()
  # list the servers
  servers = list_vbmc_servers

  for server in servers
    if server["Domain name"] == server_name
      # remove the server
      `vbmc delete #{server["Domain name"]}`
    end
  end
end

# list_vbmc_servers will list the servers registered with vbmc
# using system exec
def list_vbmc_servers
  # call vbmc list
  output = `vbmc list -f json`
  # parse the output
  json = JSON.parse(output)
  
  return json
end