# development helpers

## Setup your ssh config file locally to interact with the vagrant data center

Get your **`colony-laptop` private key** from your civo machine

```bash
scp root@<CIVO_MACHINE_PUBLIC_IP>:/root/colony/vagrant/.vagrant/machines/laptop/libvirt/private_key \
~/private_key_laptop
```

### Get your **<laptop_IP>**, in your civo machine, and add it to your ssh config file

```bash
ssh -i $YOUR_SSH_KEY_PATH root@<CIVO_MACHINE_PUBLIC_IP>

cd colony/vagrant-dc

vagrant ssh-config laptop

> You should see something like this:
Host laptop
  HostName <laptop_IP>
  User vagrant
  Port 22
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile /root/colony/vagrant/.vagrant/machines/laptop/libvirt/private_key
  IdentitiesOnly yes
  LogLevel FATAL
```

### Add the following to your ssh config file `~/.ssh/config`
```
Host colony-datacenter
  HostName <CIVO_MACHINE_PUBLIC_IP>
  User root
  ForwardAgent yes

Host colony-laptop
  Hostname <laptop_IP>
  ProxyJump colony-datacenter
  User vagrant
  ForwardAgent yes
  IdentityFile ~/private_key_laptop
```

Now, you can use Remote [VSCode Remote Development](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.vscode-remote-extensionpack) to connect to your civo machine and your data center laptop jumping through your civo machine public ip.
