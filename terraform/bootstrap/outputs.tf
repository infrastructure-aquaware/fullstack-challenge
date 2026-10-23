output "state_bucket" {
  description = "Bucket for remote Terraform state (GitHub variable TF_STATE_BUCKET)."
  value       = google_storage_bucket.tf_state.name
}

output "workload_identity_provider" {
  description = "Full provider name (GitHub variable GCP_WIF_PROVIDER)."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "deployer_service_accounts" {
  description = "Deployer per environment (GitHub environment variable GCP_DEPLOYER_SA)."
  value       = { for env, sa in google_service_account.deployer : env => sa.email }
}
