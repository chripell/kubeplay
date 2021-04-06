# Kubeplay

Current version:

* Base system: Ubuntu LTS Focal 20.04
* Kubernetes: 1.20.5
* CRI-O: 1.20
* Cilium: 1.9.5

The Vagrant configuration to setup a Kubernetes cluster is in the
directory `cluster`. It uses CRI-O as a container runtime. It uses
public networking, so be careful if you are not on a trusted
network. You can define the network interface to bridge, the number of
nodes and their IPs at the beginning of the file. You need first to
`up` the master:

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

# Networking

## Kube-Router

For pod networking, kube-router works out of the box:

```
kubectl apply -f https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter.yaml
```

It is useful to login into the kube-router pod for debugging:

```
KR_POD=$(basename $(kubectl -n kube-system get pods -l k8s-app=kube-router --output name|head -n1))
kubectl -n kube-system exec -it ${KR_POD} bash
```

## Cilium

Cilium can be quickly installed via helm, which is available also for
Arch Linux. It should be installed on the machine where you are going
to run `kubectl`. Here also the stable repository is added:

```
helm repo add stable https://charts.helm.sh/stable
helm repo add cilium https://helm.cilium.io/
helm repo update
```

then you can install Cilium with:

```
helm install cilium cilium/cilium --version 1.9.5 \
   --namespace kube-system \
   --set nodeinit.enabled=true \
   --set kubeProxyReplacement=partial \
   --set hostServices.enabled=false \
   --set externalIPs.enabled=true \
   --set nodePort.enabled=true \
   --set hostPort.enabled=true \
   --set bpf.masquerade=false \
   --set image.pullPolicy=IfNotPresent \
   --set ipam.mode=kubernetes

```

You should that cilium pods are up (there is enough one `cilium-operator`
pod till there are any more workers) and coredns is not pending:

```
$ kubectl -n kube-system get pods
cilium-node-init-q9l2m             1/1     Running   0          2m15s
cilium-operator-654456485c-bp9gw   1/1     Running   0          2m15s
cilium-operator-654456485c-wn5sd   0/1     Pending   0          2m15s
cilium-xz8fl                       1/1     Running   0          2m15s
coredns-74ff55c5b-klgjk            1/1     Running   0          4m30s
coredns-74ff55c5b-l6jtq            1/1     Running   0          4m30s
...
```

# Worker Nodes

Afterwards, you can spawn the worker nodes:

```
vagrant up node1
vagrant up node2
vagrant up node3
vagrant up node4
```

# Testing

You can use [sonobuoy](https://github.com/vmware-tanzu/sonobuoy) to
test the cluster for conformance:

```
sonobuoy run --wait --mode=certified-conformance
results=$(sonobuoy retrieve)
sonobuoy results $results
sonobuoy delete --wait
```

You should get something like:

```
Plugin: e2e
Status: passed
Total: 5667
Passed: 311
Failed: 0
Skipped: 5356

Plugin: systemd-logs
Status: passed
Total: 5
Passed: 5
Failed: 0
Skipped: 0
```

You can also test Cilium:

```
kubectl create ns cilium-test
kubectl apply -n cilium-test -f https://raw.githubusercontent.com/cilium/cilium/v1.9/examples/kubernetes/connectivity-check/connectivity-check.yaml
kubectl get pods -n cilium-test
```

check livelness of pods, afterwards you can just delete everything in
the namespace:

```
kubectl -n cilium-test delete all --all --wait
```

# Dashboard

A good way to view cluster status is using
[k9s](https://github.com/derailed/k9s). Otherwise, it is possible to
install the Kubernetes dashboard and access it via a Kubernetes proxy:

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0/aio/deploy/recommended.yaml
kubectl proxy
```

You can access the dashboard at the URL
[http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/](http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/),
however you need to use a bearer token to authenticate. You need to
create a service account named `admin-user` and bind it to the role
`cluster-admin` which was created by `kubeadm` during cluster
creation:

```
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
EOF
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF
```

You can get the bearer token (to be entered in the UI for the proxy
above) with:

```
kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}"
```

# Examples

In the `examples` directory you find various configuration files to
start *playing* with the cluster. You can deploy them using `kubectl
apply -f`.  `busybox.yaml` and `busybox-daemon.yaml` start a busybox
container as a single pod or a daemon set (one pod per node). You can
connect to it with:

```
BB_POD=$(basename $(kubectl get pods -l app=busybox1 --output name|head -n1))
kubectl exec -it ${BB_POD} sh
```

Another example is a deployment of nginx. It consist of 3
configuration files.

* `nginx-deployment.yaml` actually defines 2 pods running nginx, with
  a label `my-nginx`.
  
* `nginx-service.yaml` defines a service which makes the previous
  deployment available internally to the cluster (and discoverable via
  Core DNS). For example, you can log to the busybox pod and access
  it:
  
 ```
 $ kubectl exec -it ${BB_POD} sh
 # wget -O- my-nginx
 Connecting to my-nginx (10.106.35.192:80)
 writing to stdout
 <!DOCTYPE html>
 <html>
 <head>
 <title>Welcome to nginx!</title>
 ...

 ```

* `nginx-service-nodeport.yaml` is the simplest way to make the
  service externally available. It gets assigned to a port on the
  public IP address of the nodes. The main problem is that you have to
  preallocate ports in the range 30000 to 32768.
  
```
$ wget -O- http://192.168.0.50:30080/
--2021-04-04 17:32:39--  http://192.168.0.50:30080/
Connecting to 192.168.0.50:30080... connected.
HTTP request sent, awaiting response... 200 OK
...

```
