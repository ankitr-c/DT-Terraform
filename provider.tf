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

    # cloudflare = {
    #   source  = "cloudflare/cloudflare"
    #   version = "4.29.0"
    #   
    # }

  }
}

# provider "cloudflare" {
#   email   = "ankitraut0987@gmail.com"               // Your Cloudflare account email
#   api_key = "f9f1b286d504fa2e9c36c7060a723d4f12d60" // Your Cloudflare API key
# }

