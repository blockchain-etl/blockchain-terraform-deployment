Use this manual as a part of [main manual](README.md). It **doesn't work** on it's own. 

### Basic GKE cluster changes
All the cluster changes should be done via terragrunt/terraform or using GCP web/gcloud, not both.
Terraform knows nothing about "direct" changes via GCP web/gcloud and terraform will work to revert these changes in case of followed executions.
To perform required "direct" changes, use [official GKE docs](https://cloud.google.com/kubernetes-engine/docs), we don't cover it here.
Of course, you can perform cluster changes via terraform/terragrunt. In this case you're limited by `terragrunt.hcl` input variables. 
Some variable changes lead to complete GKE destroy-and-recreate **with all data loss**, for example `GKE_MASTER_REGION` change.
Here are some variable descriptions:
* `GKE_MASTER_REGION` - [GCP region](https://cloud.google.com/compute/docs/regions-zones) to deploy GKE master
* `GKE_NODE_LOCATIONS` - GCP zone list inside `GKE_MASTER_REGION` region, where we need to run GKE working nodes. We run one node per zone,
    thus it gives us 2 nodes with default value `["us-central1-c", "us-central1-b"]`. Pay attention to machine types, 
    some of them [are supported](https://cloud.google.com/compute/docs/regions-zones#available) in the specific zones only  
* `GKE_NODE_MACHINE_TYPE` - [machine type](https://cloud.google.com/compute/docs/machine-types) to be used with GKE nodes. 
    Adjust this value according to your load. 
* `GKE_MASTER_AUTHORIZED_NETWORKS` - IP whitelist to [access GKE master](https://cloud.google.com/kubernetes-engine/docs/how-to/authorized-networks) on network level.
    Add your IP addresses to this whitelist
* `GKE_NODE_IMAGE_TYPE` - [GKE node image](https://cloud.google.com/kubernetes-engine/docs/concepts/node-images) - operating system image to run on each GKE node

When you changed all the variables you need, it's time to apply these changes to the infrastructure. Get the list of proposed changes:
 ```bash
cd "$PROJECT_ROOT/infra/live/demo/infra"
terragrunt plan
 ```
Review carefully all the resources terraform is going to create, modify or destroy. Check there is no unexpected cluster 
destroy and recreate, which leads to in-cluster data loss. When you're good with all the proposed changes - apply them. 
It may take some time, depending on changes.
```bash
cd "$PROJECT_ROOT/infra/live/demo/infra"
terragrunt apply -auto-approve
```
### Troubleshooting 
We assume work is performed in the dedicated demo environment where data loss is acceptable. Do **not** use these instructions in 
a shared environment or production GKE cluster!  
#### GCP services/GKE provision issues
You need "Owner" permissions in your demo project to proceed w/o permission issues.

If you hit issues while creating GKE node pool - check machine types [zone support]((https://cloud.google.com/compute/docs/regions-zones#available).
Terragrunt output may be helpful too.
#### provision basic in-k8s such as helm via terragrunt
Some values of `in-k8s/terragrunt.hcl` must be the same as `infra/terragrunt.hcl`
```
K8S_CONTEXT -> K8S_CONTEXT
GKE_NODE_LOCATIONS -> K8S_REGIONAL_DISK_LOCATIONS 
``` 
But pay attention, `K8S_REGIONAL_DISK_LOCATIONS` cannot hold more than 2 zones.
#### Cryptonodes deploy issues
Here is the list of docs that may be helpful:
* [helmfile](https://github.com/roboll/helmfile)
* [helm](https://helm.sh/docs/)
* [kubectl](https://kubernetes.io/docs/reference/kubectl/overview/)
In case you hit a problem - some starting points are `kubectl get` and `kubectl describe` to pods, services, PVCs, for example
```bash
kubectl --context $KUBE_CONTEXT get namespaces
kubectl --context $KUBE_CONTEXT --namespace demo-btc-1 get pod
kubectl --context $KUBE_CONTEXT --namespace demo-btc-1 describe pod demo-btc1-bitcoind-0
kubectl --context $KUBE_CONTEXT --namespace demo-btc-1 get svc
kubectl --context $KUBE_CONTEXT --namespace demo-btc-1 describe svc demo-btc1-service
kubectl --context $KUBE_CONTEXT --namespace demo-btc-1 get pvc
kubectl --context $KUBE_CONTEXT --namespace demo-btc-1 describe pvc bitcoind-pvc-demo-btc1-bitcoind-0
``` 
`describe` messages help to understand the source of the issue usually.

Common issues are lack of resource quotas such as IPs and SSD quota. You should see corresponding messages in `kubectl ... describe ...` commands above. 
Visit [GCP console](https://console.cloud.google.com/iam-admin/quotas) to send quota increase request in this case. Another possible option is resource decrease.
See [readme](README.md#deploy-cryptonodes-via-helmfile) to decrease f.e. disk resources.

Sometimes you may want to remove all cryptonodes with all the data and start from clean k8s cluster. Use these commands to cleanup  
```bash
cd "$PROJECT_ROOT/deploy/chains"
helmfile -e demo destroy
```
Helmfile may fail to destroy helm releases in some specific state, thus you may use helm instead 
```bash
cd "$PROJECT_ROOT/deploy/chains"
helm --kube-context $KUBE_CONTEXT delete --purge demo-btc-0
helm --kube-context $KUBE_CONTEXT delete --purge demo-btc-1
helm --kube-context $KUBE_CONTEXT delete --purge demo-eth-0
helm --kube-context $KUBE_CONTEXT delete --purge demo-eth-1
```
Use following command to remove  persistent volume claims of cryptonodes, and corresponding persistent volumes in GKE. This leads to **data loss**. 
```bash
kubectl --context $KUBE_CONTEXT delete pvc -l app.kubernetes.io/instance=demo-btc-0 -A
kubectl --context $KUBE_CONTEXT delete pvc -l app.kubernetes.io/instance=demo-btc-1 -A
kubectl --context $KUBE_CONTEXT delete pvc -l app.kubernetes.io/instance=demo-eth-0 -A
kubectl --context $KUBE_CONTEXT delete pvc -l app.kubernetes.io/instance=demo-eth-1 -A
```
You can try to deploy cryptonodes again after this cleanup.

### Single cryptonode operations 
You may deploy just single cryptonode, for example, `demo-btc-1` :
```bash
cd "$PROJECT_ROOT/deploy/chains"
helmfile -e demo -l name=demo-btc-1 sync
```
Check logs via
```bash
kubectl --context $KUBE_CONTEXT -n demo-btc-1 logs --since=15s --tail=10 demo-btc-1-bitcoind-0
```
Restart cryptonode via pod delete. Pod will be recreated by [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
```bash
kubectl --context $KUBE_CONTEXT -n demo-btc-1 get pod
kubectl --context $KUBE_CONTEXT -n demo-btc-1 delete pod demo-btc-1-bitcoind-0
```
And remove this particular node
```bash
cd "$PROJECT_ROOT/deploy/chains"
helmfile -e demo -l name=demo-btc-1 destroy
```
or use helm in case of "helmfile destroy" fails
```bash
helm --kube-context $KUBE_CONTEXT delete --purge demo-btc-1
```
In case you need to remove stored cryptonode data - use following command
```bash
kubectl --context $KUBE_CONTEXT -n demo-btc-1 delete pvc -l app.kubernetes.io/instance=demo-btc-1
```

You may hit some stale resources errors in case of destroy and re-install : 
```bash
Error: release demo-btc-1 failed: object is being deleted: services "demo-btc-1-lb-p2p" already exists
```
You should wait a couple minutes after destroy in this case. 
