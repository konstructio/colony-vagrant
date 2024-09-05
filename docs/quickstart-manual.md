# Quickstart Manually Running All Steps

## Step 1 - create the data center

```sh {"id":"01J34TVHHB1FEHRVG6PDZ2RV34"}
# visit this link for your `civo-internal` account token https://dashboard.civo.com/security
## verify KUBEFIRST_TEAM_INFO is set in your shell or set it below
## verify CIVO_TOKEN is set in your shell or set it below
# export KUBEFIRST_TEAM_INFO=yourname
# export CIVO_TOKEN=

# inputs
export CIVO_REGION="nyc1"

note: the instance requires 16 CPU and 32 GB ram for the vagrant ecosystem so adjust your instance size accordingly

note: the ssh key is required to be added in civo cloud. you can manage this with `civo ssh` and update the below accordingly

civo instance create \
    --size g4s.2xlarge \
    --sshkey jedwards \
    --diskimage ubuntu-jammy \
    --script ./scripts/cloud-init \
    --initialuser root colony-$KUBEFIRST_TEAM_INFO \
    --wait
```

## Step 2 - connect to the data center

```sh {"id":"01J34TVHHB1FEHRVG6PHJRAMBA"}
# ssh onto new vm
ssh -i $PATH_TO_SSH_PRIVATE_KEY root@$CIVO_INSTANCE_PUBLIC_IP
```

## Step 3 - clone the private colony repository to the data center

```sh {"id":"01J34TVHHB1FEHRVG6PMQXBZ74"}
git clone https://github.com/konstructio/colony
# enter github username
# enter github PAT
```

## Step 4 - create and connect to laptop

*note: the user data script is running as soon as the vm is provisioned*
*and might take a minute before `vagrant` is available to run*

```sh {"id":"01J34TVHHB1FEHRVG6PPKDRRMK"}
cd /root/colony/vagrant-dc/
vagrant plugin install vagrant-libvirt

vagrant up spine01 leaf01 exit laptop
```

## Step 5 - setup laptop

first connect to laptop from the data center vm

```sh {"id":"01J34TVHHB1FEHRVG6PQD7RPK8"}
vagrant ssh laptop
```

**all laptop hosts**

:sunflower: improve the runlist: https://github.com/konstructio/colony/issues/84

```sh {"id":"01J34TVHHB1FEHRVG6PQJX14YD"}
echo "alias k=kubectl" >> ~/.bashrc
source ~/.bashrc
sudo snap install --classic kubectx
sudo snap install --classic go

# this clones the colony repository inside `laptop`
git clone https://github.com/konstructio/colony
# enter github username
# enter github PAT

# verify all pods are Completed or Running
kubens tink-system
kubectl get pods
...
download-hook-q6bk9               0/1     Completed   0          113s
download-ubuntu-jammy-xll2j       0/1     Completed   0          88s
```

### Step 6 - run colony init to get templates, secret and helm chart installation

```bash {"id":"01J34TVHHB1FEHRVG6PSH4TKFE"}
cd /home/vagrant/colony
sudo go build -o /usr/bin/colony .
export COLONY_API_KEY=<REPLACE WITH YOUR KEY FROM COLONY UI FROM https://colony-ui.mgmt-24.konstruct.io>

kubectl -n tink-system create secret generic laptop-kubeconfig  --from-file=kubeconfig=$HOME/.kube/config

go run . init
```

### Step 7 - override tinkerbell stack with our fork images

```bash {"id":"01J34TVHHB1FEHRVG6PXDG7QY3"}
# proxy mode
/home/vagrant/manifests/helm-upgrade.sh /home/vagrant/manifests/proxy-values.yaml
```

### Step 8 - verify colony pods are healthy

```sh {"id":"01J34TVHHB1FEHRVG6PY6660MR"}
kubens tink-system
kubectl get pods
```

if all pods are healthy, you can run exit to return to the datacenter vm

```text {"id":"01J34TVHHB1FEHRVG6PZFJA6V5"}
exit
```

### Step 9 - power on machine1 and autodiscover

```sh {"id":"01J34TVHHB1FEHRVG6Q0QS1GC3"}
# from datacenter vm
cd /root/colony/

sudo go build -o /usr/bin/colony .

cd vagrant-dc

colony power-on
```

Within 60 seconds, you should see the machines discover in the colony UI on the assets page

### Step 10 - flash an operating system onto the hardware

in the colony user interface, go to the assets page to view the discovered hardware.

check the checkbox for the available hardware and select the ubuntu-focal template.

apply the template.

### Step 11 - open a vnc tunnel

open a new isolated terminal on your laptop

replace the values for the below two export commands, and run this to open a tunnel

```sh {"id":"01J34TVHHB1FEHRVG6Q2997ZKG"}
export DC_VM_IP=212.2.243.92 # get this value from civo console
export MACHINE_PORT=5905 # get this value from vagrant up output. look for `==> machine1:  -- Graphics Port:`
ssh -i ~/.ssh/id_ed25519 root@${DC_VM_IP} -L ${MACHINE_PORT}:127.0.0.1:${MACHINE_PORT}
```

then go to another terminal and run

```sh {"id":"01J34TVHHB1FEHRVG6Q6916QGX"}
export MACHINE_PORT=5901
open vnc://127.0.0.1:$MACHINE_PORT
```

Notes to iterate demo from this point:

- vagrant destroy machine1
- vagrant ssh laptop
- k delete wf --all
- k delete hw --all
- exit back to datacenter
- connect to cockroach from local
- delete workflows and hardwares where account_id=xxx
- check ui, assets are empty
- return to step 10 when demoing
