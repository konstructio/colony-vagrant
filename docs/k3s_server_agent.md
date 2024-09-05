# k3s cluster with server and agents

Return to [README](../README.md)

## Create templates

```bash
vagrant@ubuntu2204:~/manifests$ k apply -f templates/ubuntu-focal-k3s-agent.yaml
vagrant@ubuntu2204:~/manifests$ k apply -f templates/ubuntu-focal-k3s-server.yaml
vagrant@ubuntu2204:~/manifests$ k apply -f k3s/server/

hardware.tinkerbell.org/machine1 created
workflow.tinkerbell.org/machine1 created

# remember to start machine1 in the host machine, with vagrant up machine1

NAME       TEMPLATE                  STATE
machine1   ubuntu-focal-k3s-server   STATE_SUCCESS
```

## Get the token from the server and replace it in the agent workflow

in host machine

```bash
vagrant ssh-config
```

Go to the machine1 (k3s server) and get the token

```bash

ssh tink@<MACHINE1-IP> # tink/tink

tink@machine1:~$ sudo cat /var/lib/rancher/k3s/server/node-token # copy the token and use that to replace in k3s/agent1/workflow.yaml

tink@machine1:~$ exit
logout
Connection to 192.168.121.7 closed.
``` 

## Start the agent1

in laptop

```bash
vagrant@ubuntu2204:~/manifests$ nano k3s/agent1/workflow.yaml
vagrant@ubuntu2204:~/manifests$ nano k3s/agent2/workflow.yaml
vagrant@ubuntu2204:~/manifests$ k apply -f k3s/agent1/

hardware.tinkerbell.org/machine2 created
workflow.tinkerbell.org/machine2 created

# remember to start machine1 in the host machine, with vagrant up machine1

NAME       TEMPLATE                  STATE
machine2   ubuntu-focal-k3s-server   STATE_SUCCESS
```

## Access to k3s server

Check when the agent is ready

```bash
tink@machine1:~$ sudo kubectl get nodes -w
NAME       STATUS   ROLES                  AGE     VERSION
machine1   Ready    control-plane,master   9m58s   v1.29.4+k3s1
machine2   NotReady   <none>                 0s      v1.29.4+k3s1
machine2   NotReady   <none>                 0s      v1.29.4+k3s1
machine2   NotReady   <none>                 0s      v1.29.4+k3s1
machine2   NotReady   <none>                 0s      v1.29.4+k3s1
machine2   NotReady   <none>                 0s      v1.29.4+k3s1
machine2   Ready      <none>                 0s      v1.29.4+k3s1
machine2   Ready      <none>                 0s      v1.29.4+k3s1
machine2   Ready      <none>                 0s      v1.29.4+k3s1
machine2   Ready      <none>                 0s      v1.29.4+k3s1
machine2   Ready      <none>                 2s      v1.29.4+k3s1

```

