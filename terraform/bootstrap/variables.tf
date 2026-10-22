variable "project_id" {
  type        = string
  description = "GCP project ID that hosts every environment."
}

variable "region" {
  type        = string
  description = "GCP region for buckets."
  default     = "us-central1"
}

variable "github_repository" {
  type        = string
  description = "GitHub repository allowed to deploy, as owner/name."
  default     = "infrastructure-aquaware/fullstack-challenge"
}

variable "environments" {
  type        = list(string)
  description = "Environments that get their own deployer identity. Each matches a branch name."
  default     = ["devel", "stage"]
}
