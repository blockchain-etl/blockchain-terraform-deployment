Here is basic HOWTO use [helmfile](https://github.com/roboll/helmfile) 

Requirements:
* [install](https://github.com/roboll/helmfile#installation) helmfile
* configure GKE context, if not present
* Add [helm-gcs](https://github.com/hayorov/helm-gcs#installation) plugin
* install tiller(helm agent) into GKE cluster, if not present

Change dir to `/deploy`, adjust [helmfile.yaml](helmfile.yaml), you may need to pay attention to
* repositories, you should add your custom helm repo here
* kubeContext, specify your context here
* `values-...-staging-....yaml`, specify IPs for load balancers, use  `gcloud compute addresses list` to get the list of pre-created IPs.

Workflow:
* deploy all the releases:
```shell script
helmfile sync
```
command will block and wait for every release to spin up pods and services 
* deploy single release, `staging-eth1` f.e.:
```shell script
helmfile -l name=staging-eth1 sync
```
* status of all releases
```shell script
helmfile status
```
* destroy all releases
```shell script
helmfile destroy
```
* destroy single release, `staging-btc0` f.e.:
```shell script
helmfile -l name=staging-btc0 destroy
```
