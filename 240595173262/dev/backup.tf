terraform {
  backend "s3" {
    bucket = "elsevier-tio-shobha-development-240595173262"
    key    = "tfstate/demo.tfstate"
    region = "us-east-1"
  }
}
