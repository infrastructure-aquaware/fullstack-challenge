# Per-environment static hosting on Cloud Storage.
# The same configuration is applied once per environment (devel, stage); each
# environment has its own state prefix, buckets, deployer identity and tfvars.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # bucket and prefix are passed with -backend-config (see README).
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    app         = var.app_name
    environment = var.environment
    managed_by  = "terraform"
  }
}

locals {
  name_prefix = "${var.project_id}-${var.app_name}-${var.environment}"

  content_types = {
    css   = "text/css"
    html  = "text/html"
    ico   = "image/x-icon"
    js    = "application/javascript"
    json  = "application/json"
    map   = "application/json"
    png   = "image/png"
    svg   = "image/svg+xml"
    txt   = "text/plain"
    woff  = "font/woff"
    woff2 = "font/woff2"
  }

  build_files = fileset(var.build_dir, "**")
}

# Audit/access logs: receives Cloud Storage usage logs from the site bucket.
resource "google_storage_bucket" "access_logs" {
  name                        = "${local.name_prefix}-access-logs"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy_logs

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
}

# Google's log writer may only create objects; it cannot read or delete them.
resource "google_storage_bucket_iam_member" "access_logs_writer" {
  bucket = google_storage_bucket.access_logs.name
  role   = "roles/storage.objectCreator"
  member = "group:cloud-storage-analytics@google.com"
}

resource "google_storage_bucket" "site" {
  name                        = "${local.name_prefix}-site"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  # Public reads are impossible unless public_access is explicitly enabled.
  public_access_prevention = var.public_access ? "inherited" : "enforced"

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }

  logging {
    log_bucket        = google_storage_bucket.access_logs.name
    log_object_prefix = "${var.environment}/site"
  }

  depends_on = [google_storage_bucket_iam_member.access_logs_writer]
}

# Anonymous read-only access, only while public_access = true (the recording window).
resource "google_storage_bucket_iam_member" "public_read" {
  count = var.public_access ? 1 : 0

  bucket = google_storage_bucket.site.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_object" "build" {
  for_each = local.build_files

  bucket = google_storage_bucket.site.name
  name   = each.value
  source = "${var.build_dir}/${each.value}"

  content_type = lookup(
    local.content_types,
    lower(element(split(".", each.value), length(split(".", each.value)) - 1)),
    "application/octet-stream"
  )

  # Hashed assets under static/ are immutable; everything else must revalidate.
  cache_control = startswith(each.value, "static/") ? "public, max-age=31536000, immutable" : "no-cache"
}
