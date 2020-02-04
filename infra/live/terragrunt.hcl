remote_state {
  backend = "gcs"
  config = {
    bucket      = "bucket-to-store-tf-state"
    prefix      = "${path_relative_to_include()}"
    # use to deploy from dedicated service aacount
    credentials = "${get_env("HOME", "")}/path/to/key.json"
  }
}
