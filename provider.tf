#----------------------GCP Provider------------------------------

# provider "google" {
#   project = var.project_id
#   region  = var.region_name
# }

terraform {
  required_providers {
    ansible = {
      version = "~> 1.2.0"
      source  = "ansible/ansible"
    }
  }
}
