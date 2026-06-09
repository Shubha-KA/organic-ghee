# Azure Deployment Runbook

Purpose
- Step-by-step operational runbook to take the repository from local to production Azure deployment.

Audience
- Cloud Engineers, DevOps, SREs, Security Engineers.

Prerequisites
- Azure CLI installed and logged in: `az login`.
- Git installed and access to the repository with permissions to create workflows and secrets.
- A GitHub organization or repository admin able to configure OIDC and environments.
- Local Node.js toolchain for app build: Node.js >= 16, npm/yarn.

1. Azure prerequisites (summary)
- Subscription(s): a single or multiple subscriptions as per organizational policy. Recommended separation:
  - Shared services subscription (for remote state, networking)
  - Landing zone / platform subscription (for platform infra: Key Vault, central monitoring)
  - Workload subscription (for the production app resources)
- Required roles (assign using Azure Portal or `az role assignment`):
  - `Owner` or `Contributor` for bootstrapper account (short-lived)
  - `Storage Account Contributor` for backend storage admin
  - `Key Vault Contributor` for Key Vault administration
  - `Application Administrator` / `Cloud Application Administrator` for Entra App registration tasks (or Global Admin for federation)

2. Bootstrap deployment (remote state)

Goal: create a small, well-protected Resource Group and Storage Account that will host Terraform state and provide locking via Azure Blob leases.

Steps (Portal)
- Portal navigation: Subscription -> Resource groups -> + Create -> fill name `tfstate-rg-<org>` -> Create
- Portal navigation: Storage Accounts -> + Create -> Resource group: `tfstate-rg-<org>` -> Name: `tfstate<suffix>` -> Performance: Standard -> Replication: LRS (or ZRS for high durability) -> Networking: selected networks or private endpoints recommended -> Advanced: enable blob versioning and soft delete -> Review + Create
- After creation: Storage account -> Containers -> + Container -> Name: `tfstate` -> Access level: Private

Commands (CLI)
```bash
az group create -n tfstate-rg -l eastus
az storage account create -n tfstate<unique> -g tfstate-rg --sku Standard_LRS --encryption-services blob --min-tls-version TLS1_2
az storage container create --name tfstate --account-name tfstate<unique>
```

State locking and versioning
- The `azurerm` backend uses Blob leases to lock state; only one operation can acquire the lease.
- Enable Blob soft-delete and versioning on the storage account to protect state from accidental deletion or corruption.
- Recovery strategy: enable resource locks on the backend resource group, use a separate subscription for state if possible, regularly export state to a secure backup (e.g., Azure Recovery Services or periodic blob copy to another storage account/region).

Before every state migration, import, or recovery operation, create a local encrypted backup outside source control:

```powershell
New-Item -ItemType Directory -Force .terraform-backups
terraform -chdir=terraform workspace select dev
terraform -chdir=terraform state pull > ".terraform-backups/dev-$(Get-Date -Format yyyyMMdd-HHmmss).tfstate"
terraform -chdir=terraform state list
terraform -chdir=terraform plan -refresh-only -var-file="environments/dev/terraform.tfvars"
```

Never commit state files or saved plan files. Do not use `state rm`, `state push`, `import`, or `force-unlock` without a reviewed backup and explicit approval.

3. GitHub configuration (high level)
- Create repository and ensure branch protection is enabled on `main` and release branches.
- Configure GitHub OIDC (see detailed guide in `security-hardening-guide.md`).
- Configure GitHub Environment variables for `dev` and `prod`: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `AZURE_WEBAPP_NAME`, `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, and `TFSTATE_CONTAINER`.
- Configure the environment secret `DATABASE_CONNECTION_STRING` only while an externally managed MongoDB database is used. Terraform stores it in Key Vault; the application receives only a Key Vault reference.
- Protect the `prod` GitHub Environment with required reviewers. OIDC federation uses the exact subjects `repo:Shubha-KA/organic-ghee:environment:dev` and `repo:Shubha-KA/organic-ghee:environment:prod`.

4. Microsoft Entra ID
- Create App Registration and Service Principal if required for non-OIDC scenarios (see `security-hardening-guide.md`).

5. Terraform deployment order (summary)
- Bootstrap remote state (see above)
- From `terraform/` directory: init backend, create workspaces, apply `dev` then `prod` following the sequences in `production-readiness-review.md`.

6. Application deployment (summary)
- Build the Node.js app locally or in CI: `npm ci` -> `npm run build` (if applicable) -> generate artifact (zip) for App Service.
- CI will use GitHub Actions to build and push package to App Service via `az webapp deploy` or via deployment center with ZIP deploy.

7. Post-deployment verification
- Use `az webapp show` to confirm state and `curl` to hit health endpoint.
- Verify Managed Identity has access to Key Vault and can fetch secrets.

Appendices
- See `security-hardening-guide.md` for Key Vault and network hardening steps.
- See `monitoring-guide.md` for setting up Application Insights and Log Analytics.
