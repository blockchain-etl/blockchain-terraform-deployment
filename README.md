Howto deploy full env from scratch. We assume new `demo` env in this manual. 

## Client Software Requirements:
* MacOS or Linux. Windows supports all the tools but is out of scope of this manual
* git
* [terraform](https://www.terraform.io/downloads.html)
* [terragrunt](https://github.com/gruntwork-io/terragrunt#install-terragrunt)
* [gcloud](https://cloud.google.com/sdk/install) 
* kubectl (version from gcloud is ok)
* [helm](https://helm.sh/docs/using_helm/#installing-helm), version 2.x, version 3 isn't supported now. Check `helm version -c`
* [helmfile](https://github.com/roboll/helmfile#installation) 
* [helm-gcs](https://github.com/hayorov/helm-gcs#installation) plugin
* Please follow "Before you begin" part of [GCP manual](https://cloud.google.com/kubernetes-engine/docs/how-to/iam) (gcloud configuration)

## Top-level road-map: 
* create GCP project, configure gcloud to this project
* clone this repo, configure terraform state storage, create/adjust terragrunt manifests
* provision GCP services and GKE via terragrunt
* provision basic in-k8s such as helm via terragrunt
* deploy cryptonodes via helmfile
* check logs
* teardown

## Let's dive in:
### Create project
and configure gcloud to use this project by defaul
```bash
export GCP_PROJECT_ID=test-baas-d1
gcloud projects create $GCP_PROJECT_ID --set-as-default
```
Add billing to this project. You may use web console to do so, here is cli version to connect new project to first open billing account
```bash
gcloud beta billing accounts list --filter=open=true  --format='get(name)' | xargs -I'{}' gcloud beta billing projects link $GCP_PROJECT_ID --billing-account '{}'
```
Allow terraform and other apps to work via gcloud sdk, if not done before
```bash
gcloud auth application-default login
```
### Clone this repo
```bash
git clone https://github.com/blockchain-etl/blockchain-terraform-deployment 
cd blockchain-terraform-deployment
```
* Configure/check remote terraform state storage. We use [remote terraform state storage](https://www.terraform.io/docs/state/remote.html),
 namely [gcs backend](https://www.terraform.io/docs/backends/types/gcs.html). You need an access to storage bucket. 
 In this manual we'll use bucket created in the same project, but keep in mind - it's better to store terraform state out of terraform-controlled project.
 Run this code to create GCS bucket ( we use `us-central1` bucket location here, change it to region where you're going to deploy infrastructure ):
    ```bash
    export TF_STATE_BUCKET=${GCP_PROJECT_ID}-tf
    gsutil mb -p ${GCP_PROJECT_ID} -c standard -l us-central1 gs://${TF_STATE_BUCKET}
    gsutil versioning set on gs://${TF_STATE_BUCKET}
    ```  
    and configure terraform to use it:
    ```bash
    sed -i "" -e "s/bucket-to-store-tf-state/$TF_STATE_BUCKET/g" infra/live/terragrunt.hcl  
    cat infra/live/terragrunt.hcl 
    ```  
    If you want to use another storage - adjust `infra/live/terragrunt.hcl` accordingly and ensure you have full access to this storage.
* Create/adjust terragrunt manifests
    ```bash
    cd infra/live
    mkdir demo demo/in-k8s demo/infra
    cp staging/in-k8s/terragrunt.hcl demo/in-k8s/
    cp staging/infra/terragrunt.hcl demo/infra/
    ```
    Perform following replacements(see automated replacement below):
    `your-staging-project` with project name `test-baas-d1` in both `.hcl` files
    `staging` with `demo` in `demo/infra/terragrunt.hcl`
    Here are `sed` commands to perform replacement :
    ```bash
    sed -i "" -e "s/your-staging-project/$GCP_PROJECT_ID/g" demo/in-k8s/terragrunt.hcl demo/infra/terragrunt.hcl
    sed -i "" -e 's/staging/demo/g' demo/infra/terragrunt.hcl
    ```

### Provision GCP services and GKE cluster
Review inputs in `demo/infra/terragrunt.hcl` and adjust as needed. Pay attention to regions, zones, machine type. 
You need to adjust `GKE_MASTER_AUTHORIZED_NETWORKS` with your IP address ranges to additionally restrict GKE master API access by IP whitelist. 
Use `0.0.0.0/0` to effectively allow connection to GKE master API from any IP on network level. Access is still restricted by Google auth. 
Ensure you get GCP credentials earlier via `gcloud auth application-default login` and continue : 
 ```bash
cd demo/infra
terragrunt plan
 ```
Review  resources to create and proceed when everything looks fine. It usually takes 10-30min
```bash
terragrunt apply -auto-approve
```

### Deploy basic in-k8s services
```bash
cd ../in-k8s
terragrunt plan
```
Review resources to create and proceed when everything looks fine. It should finish up in seconds.
```bash
terragrunt apply -auto-approve
```

### Deploy cryptonodes via helmfile
```bash
cd ../../../.. # repo root
cd deploy/chains
mkdir -p demo # should be created by terraform earlier
cp staging/helmfile.yaml demo/helmfile.yaml
```
Replace release names in `helmfile.yaml` via 
```bash
sed -i "" -e 's/staging/demo/g' demo/helmfile.yaml
``` 
We also add disk limit into all nodes, as default project SSD quota is low. Add
```yaml
persistence:
  size: "50Gi"
```
to all `values-*.yaml` files in `demo` directory.
This action isn't required in GCP projects with increased SSD disk limits, but here is shell snippet anyway:
```bash
for filename in demo/values-*.yaml;do
cat << 'EOF' >> $filename
persistence:
  size: "50Gi"
EOF
done
``` 
Adjust `helmfile.yaml` in `deploy/chains` for new env, when required:
- add new env `demo` into `environments` section
- add `- demo/helmfile.yaml` into `helmfiles` section

Now we're ready to deploy cryptonodes. Check helm release status to confirm nothing is deployed yet :
```bash
export kube_context=$GCP_PROJECT_ID-baas0
helmfile -e demo status
```
and deploy charts via
```bash
helmfile -e demo -l chain=btc sync
helmfile -e demo -l chain=eth sync
```
It may take some time and even fail in case of helm overload, some wrong values, project quotas.
In this case you should find the source of the issue, correct it and start again. 
Some starting points are `kubectl get` and `kubectl describe` to pods, services, PVCs.
You may require helm invocations to remove failed releases, for example (remove comment to run)
```bash
#helm -e demo delete --purge demo-btc0 demo-btc1 demo-eth0 demo-eth1
```
and then re-run "helmfile ... sync" commands from above.

We should get namespaces and pods as shown on the diagram [<img src="./images/k8s-NS.svg">](./images/k8s-NS.svg)

### Check our cryptonodes
```bash
kubectl -n demo-eth-0 get pod,svc
kubectl -n demo-eth-1 get pod,svc
kubectl -n demo-btc-0 get pod,svc
kubectl -n demo-btc-1 get pod,svc
```
Check logs
```bash
kubectl -n demo-eth-0 logs --since=15s --tail=10 demo-eth-0-parity-0
kubectl -n demo-eth-1 logs --since=15s --tail=10 demo-eth-1-parity-0 
kubectl -n demo-btc-0 logs --since=15s --tail=10 demo-btc-0-bitcoind-0
kubectl -n demo-btc-1 logs --since=15s --tail=10 demo-btc-1-bitcoind-0
```
Check CPU & memory usage by pods
```bash
kubectl top pod -A
```

### Teardown
* remove helm releases
```bash
helmfile -e demo destroy
```
* remove persistent volumes, this removes all the data effectively(blockchain data loss happens here)
```bash
kubectl delete pv --all --wait=false
```
* teardown infrastructure via terragrunt, it takes 10-30 minutes
```bash
cd ../../infra/live/demo/infra/
terragrunt destroy
```
Answer `yes` after reviewing all the resources terraform is going to delete. It takes a couple minutes.
In case you hit VPC destroy error such as 
```bash
Error: Error waiting for Deleting Network: The network resource 'projects/test-baas-d1/global/networks/baas0' is already being used by 'projects/test-baas-d1/global/firewalls/k8s-fw-ad83ceb911d9211eaa09042010a80018'
```
You need to remove firewall rules via following snippet (adjust `network=baas0` if you used another VPC name during deployment)
```bash
gcloud compute firewall-rules list --project=$GCP_PROJECT_ID --filter=network=baas0 --format='get(name)'|xargs gcloud compute firewall-rules delete --project=$GCP_PROJECT_ID
```
and run `terragrunt destroy` again. It should finish w/o errors this time.
* remove project 
```bash
gcloud projects delete $GCP_PROJECT_ID
```
