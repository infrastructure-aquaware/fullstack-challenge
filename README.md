# FullStack DevOps Challenge — Orlando Hurtado

Prepared and submitted by Orlando Hurtado.

CI/CD for **RDICIDR** (a React subnet calculator) on Google Cloud. GitHub Actions runs CI on every pull request; Terraform deploys two isolated environments, `devel` and `stage`, as static sites on Cloud Storage, each logging access to its own audit bucket.

## Solution overview

| Concern | Approach |
|---|---|
| CI | `ci.yml` runs on every PR with separate steps: `npm install`, `npm run lint`, `CI=true npm run test`, `npm run build`. |
| Branch policy | CI fails PRs into `stage` not from `devel`, and PRs into `devel` not from `feature/*` / `bugfix/*`. Rulesets block direct pushes. |
| CD | `cd.yml` runs on merge to `devel` / `stage`: build, then `terraform apply` for that environment. |
| Environments | One Terraform root (`terraform/app`) per environment: own tfvars, state prefix, buckets and deployer identity. |
| Hosting | One Cloud Storage bucket per environment; Terraform uploads the build with explicit content types and cache headers. |
| Access logs | Cloud Storage usage logs go to a separate private, versioned bucket with 30-day retention. |
| Identity | GitHub OIDC → Workload Identity Federation; no keys. Each deployer only works from its own branch. |
| Public window | `public_access=false` by default (public access prevention enforced); enabled only for the recording. |

<img width="945" height="593" alt="image" src="https://github.com/user-attachments/assets/05ddcd45-1fc6-40e6-a1ce-cc21358cbf2b" />


## Repository layout

```
.github/workflows/ci.yml        PR pipeline + branch policy
.github/workflows/cd.yml        Deploy on merge to devel / stage
.github/workflows/teardown.yml  Remove public access or destroy an environment
terraform/bootstrap/            One-time: state bucket, OIDC trust, deployer accounts
terraform/app/                  Per-environment hosting + access logs (envs/*.tfvars)
src/, public/, package.json     The React application (from the challenge, unchanged)
```

## 1. Run locally

Requires Node 15.5.1 / npm 7 (`.nvmrc`, enforced by `engines`). On Apple Silicon, use the CI image:

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/app -v rdicidr_nm:/app/node_modules \
  -w /app node:15.5.1 bash -c "npm install && npm run lint && CI=true npm run test && npm run build"
```

## 2. Bootstrap GCP (once)

```bash
gcloud auth application-default login
cd terraform/bootstrap && terraform init && terraform apply && terraform output
```

Creates the state bucket `<project>-tfstate`, the Workload Identity pool `github` (provider `github-oidc`, trusting this repository only) and the service accounts `gha-deploy-devel` / `gha-deploy-stage`. Bootstrap state stays local.

## 3. Configure GitHub

| Scope | Variable | Value |
|---|---|---|
| Repository | `GCP_PROJECT_ID` | GCP project ID |
| Repository | `GCP_WIF_PROVIDER` | `terraform output -raw workload_identity_provider` |
| Repository | `TF_STATE_BUCKET` | `terraform output -raw state_bucket` |
| Environment `devel` / `stage` | `GCP_DEPLOYER_SA` | matching email from `deployer_service_accounts` |
| Environment `devel` / `stage` | `PUBLIC_ACCESS` | `false` (`true` only during the recording) |

No secrets are needed. Add rulesets on `devel` and `stage`: require a PR with 1 approval, require the `Branch policy` and `Install, lint, test, build` checks, block force pushes and deletions, and allow no bypass. Set `devel` as the default branch.

## 4. CI and deployment

Every PR runs `ci.yml`; each step shows as its own pass/fail line in the Checks tab.

1. `feature/x` → PR into `devel` → green CI + review → merge → CD deploys **devel**.
2. `devel` → PR into `stage` → green CI + review → merge → CD deploys **stage**.

CD builds with `PUBLIC_URL=https://storage.googleapis.com/<site-bucket>` so asset paths resolve, then runs `terraform apply` with backend prefix `app/<env>`. The job summary prints the URL: `https://storage.googleapis.com/<project>-rdicidr-<env>-site/index.html`.

Manual equivalent:

```bash
GENERATE_SOURCEMAP=false PUBLIC_URL=https://storage.googleapis.com/<project>-rdicidr-devel-site npm run build
cd terraform/app
terraform init -backend-config="bucket=<project>-tfstate" -backend-config="prefix=app/devel"
terraform apply -var-file=envs/devel.tfvars -var public_access=true
```

## 5. Access logging

Each site bucket delivers usage logs to `<project>-rdicidr-<env>-access-logs/<env>/site*`. Only Google's `cloud-storage-analytics@google.com` group can write there, as object creator; nobody can make the bucket public. Usage logs capture anonymous requests too (client IP, method, URI, status, bytes) and are **delivered hourly**:

```bash
gcloud storage ls gs://<project>-rdicidr-devel-access-logs/devel/
gcloud storage cat "gs://<project>-rdicidr-devel-access-logs/devel/site_usage_*" | head
```

Bucket and IAM changes are also recorded in Cloud Audit Logs (Admin Activity).

## 6. Teardown

After the recording:

1. Set `PUBLIC_ACCESS=false` on both environments.
2. Run **Actions → Teardown** from `devel`, then from `stage`, with mode `disable-public`. It empties the site, re-enforces public access prevention, and fails if the site still returns 200.
3. **Keep the site bucket until the next hourly log delivery.** Logs for a bucket deleted before delivery are not written.
4. Optionally run Teardown again with mode `destroy` afterwards. Log buckets are kept unless destroyed with `-var force_destroy_logs=true`.

Verify:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://storage.googleapis.com/<project>-rdicidr-<env>-site/index.html   # 403/404
gcloud storage buckets describe gs://<project>-rdicidr-<env>-site --format='value(public_access_prevention)'      # enforced
```

## Security

- No long-lived credentials. WIF accepts tokens only from this repository, and each deployer only from `refs/heads/<env>`.
- Deployers hold `roles/storage.admin` (bucket creation and bucket IAM) and object access to state. They have no compute, IAM-admin or network rights.
- Uniform bucket-level access is on everywhere. Public access prevention is `enforced` except on a site bucket during its public window.
- Log and state buckets are versioned. The log writer cannot read or delete logs.
- JFrog/Artifactory is not used: the static bundle is deployed straight from CI, with no package or image to publish.

## Assumptions, costs and limitations

- **Assumptions:** one GCP project in `us-central1`, with environments isolated by naming, state, identity and buckets. The app code is used as provided.
- **Costs:** a few cents per month. That covers about 1 MB of standard storage, negligible requests and egress, and KB-scale logs. Workload Identity Federation and IAM are free, and there's no load balancer or compute.
- **No custom domain or CDN:** sites are served from `storage.googleapis.com`. An external HTTPS load balancer with a backend bucket, managed certificate and Cloud CDN would add those (from about $18/month).
- **Hourly log delivery:** requests made during a short recording appear in the log bucket afterwards.
- **Broad deployer role:** `roles/storage.admin` is project-wide. A custom role or a project per environment would narrow it.
- **Old toolchain:** Node 15 and `react-scripts` 4 are end-of-life. They are kept because the app pins them with `engine-strict`.

## References

**Google Cloud**
- [Workload Identity Federation with deployment pipelines](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)
- [Usage logs & storage logs](https://cloud.google.com/storage/docs/access-logs)
- [Public access prevention](https://cloud.google.com/storage/docs/public-access-prevention)

**Terraform**
- [Partial backend configuration](https://developer.hashicorp.com/terraform/language/backend#partial-configuration)
- [`google_iam_workload_identity_pool_provider`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_provider)
- [`google_storage_bucket`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket)
