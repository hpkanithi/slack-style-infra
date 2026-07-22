terraform {
  backend "s3" {
    bucket       = "my-slack-style-tfstate-177362732651-us-east-2-an"
    key          = "slack-style/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
  }
}