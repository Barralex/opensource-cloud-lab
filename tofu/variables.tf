# Configuration variables
# Values are passed via terraform.tfvars or environment variables

variable "region" {
  description = "DigitalOcean region (nyc1, sfo1, ams3, etc.)"
  type        = string
  default     = "nyc1"
}

variable "environment" {
  description = "Environment: dev, staging, prod"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource tags"
  type        = string
  default     = "oss-cloud-lab"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_ed25519_oss_cloud_lab.pub"
}
