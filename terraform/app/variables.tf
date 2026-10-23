variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region for buckets."
  default     = "us-central1"
}

variable "environment" {
  type        = string
  description = "Environment name; also the Git branch that deploys it."

  validation {
    condition     = contains(["devel", "stage"], var.environment)
    error_message = "environment must be \"devel\" or \"stage\"."
  }
}

variable "app_name" {
  type        = string
  description = "Short application name used in resource names."
  default     = "rdicidr"
}

variable "build_dir" {
  type        = string
  description = "Path to the React production build (output of npm run build)."
  default     = "../../build"
}

variable "public_access" {
  type        = bool
  description = "Grant anonymous read access to the site. Keep false except during the recording window."
  default     = false
}

variable "log_retention_days" {
  type        = number
  description = "Days to keep access logs before lifecycle deletion."
  default     = 30
}

variable "force_destroy_logs" {
  type        = bool
  description = "Allow terraform destroy to delete the access-log bucket while it still holds logs."
  default     = false
}
