
This is a Vagrant configuration to setup a Kubernetes cluster which
uses CRI-O as a container runtime. It uses public networking, so be
careful if you are not on a trusted network. You can define the
network interface to bridge, the number of nodes and their IPs at the
beginning of the file. You need first to `up` the master:

```
vagrant up master
```

because it creates some files that are needed for the nodes. It also
leaves the configuration file `admin.conf` you need to reference from
`kubectl` on the host (please note that `kubectl` on the host is not
installed by this script). If you don't have other clusters, you can
just copy it as the global config:

```
cp admin.conf $HOME/.kube/config
```

For pod networking, kube-router works out of the box:

```
kubectl apply -f https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter.yaml
```

Afterwards, you can spawn the worker nodes:

```
vagrant up node1
vagrant up node2
vagrant up node3
vagrant up node4
```
