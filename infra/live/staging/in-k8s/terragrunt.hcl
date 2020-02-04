terraform {
  source = "github.com/blockchain-etl/blockchain-terraform.git//in-k8s?ref=master"
}

include {
  path = find_in_parent_folders()
}

inputs = {
  GCP_PROJECT_ID = "your-staging-project"
  K8S_CONTEXT = "your-staging-project-baas0"
  K8S_REGIONAL_DISK_LOCATIONS = "us-central1-b, us-central1-c"
  K8S_SC_SUFFIX = "us-central1-bc"
  K8S_TILLER_SA_NAME = "tiller"
}
