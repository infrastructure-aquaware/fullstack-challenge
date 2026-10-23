# One-time setup, applied manually by a project admin with local state.
# Creates the remote state bucket, the GitHub OIDC trust (Workload Identity
# Federation) and one deployer service account per environment. No keys are
# created: GitHub Actions exchanges its OIDC token for short-lived credentials.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  apis = [
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "storage.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.apis)

  service            = each.value
  disable_on_destroy = false
}

# Remote state for every environment (separated by prefix).
resource "google_storage_bucket" "tf_state" {
  name                        = "${var.project_id}-tfstate"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Only tokens from this repository are accepted at all.
  attribute_condition = "assertion.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# One deployer per environment, so a devel run can never act as stage.
resource "google_service_account" "deployer" {
  for_each = toset(var.environments)

  account_id   = "gha-deploy-${each.value}"
  display_name = "GitHub Actions deployer (${each.value})"

  depends_on = [google_project_service.required]
}

# Each deployer can only be impersonated by workflows running on its own branch.
resource "google_service_account_iam_member" "wif_binding" {
  for_each = toset(var.environments)

  service_account_id = google_service_account.deployer[each.value].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.ref/refs/heads/${each.value}"
}

# Deployers manage Cloud Storage only (create buckets, objects and bucket IAM).
resource "google_project_iam_member" "deployer_storage" {
  for_each = toset(var.environments)

  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.deployer[each.value].email}"
}

# Read/write Terraform state.
resource "google_storage_bucket_iam_member" "deployer_state" {
  for_each = toset(var.environments)

  bucket = google_storage_bucket.tf_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.deployer[each.value].email}"
}
