output "site_bucket" {
  description = "Bucket that serves the application."
  value       = google_storage_bucket.site.name
}

output "access_log_bucket" {
  description = "Bucket that receives Cloud Storage usage (access) logs."
  value       = google_storage_bucket.access_logs.name
}

output "site_url" {
  description = "Public URL (works only while public_access = true)."
  value       = "https://storage.googleapis.com/${google_storage_bucket.site.name}/index.html"
}

output "public_access" {
  description = "Whether anonymous read access is currently granted."
  value       = var.public_access
}
