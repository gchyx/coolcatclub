terraform {
  backend "s3" {
    bucket         = "coolcatclub-terraform-state" # manually created in the console
    key            = "state/terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
  }
}