# Organic Ghee

Organic Ghee is a Node.js and Express ordering application with Handlebars
views, Mongo-compatible persistence, Microsoft Entra ID administration, and
Azure infrastructure managed by Terraform.

## Repository Structure

| Path | Purpose |
| --- | --- |
| `.github/workflows/` | Application and Terraform GitHub Actions workflows |
| `docs/` | Deployment, authentication, and operational guidance |
| `functions/` | Queue-triggered Azure Function |
| `public/` | Browser assets |
| `src/auth/` | Microsoft Entra ID authentication |
| `src/middleware/` | Customer and administrator authorization |
| `src/models/` | Mongoose data models |
| `src/routers/` | Express routes |
| `src/services/` | Azure Blob Storage and Queue integrations |
| `terraform/backend/` | Remote state bootstrap configuration |
| `terraform/environments/` | Development and production variable files |
| `terraform/modules/` | Reusable Azure resource modules |
| `views/` | Handlebars templates |

## Local Development

Install dependencies:

```powershell
npm ci
```

Configure the required environment variables, including `SESSION_SECRET` and
`AZURE_COSMOS_CONNECTIONSTRING`, then start the application:

```powershell
npm start
```

The application listens on `PORT`, or port `8000` when `PORT` is unset. Its
health endpoint is `/health`.

## Terraform

Bootstrap the remote state resources:

```powershell
terraform -chdir=terraform/backend init
terraform -chdir=terraform/backend plan
terraform -chdir=terraform/backend apply
```

Initialize the main Terraform configuration with the backend values produced
by the bootstrap deployment:

```powershell
terraform -chdir=terraform init `
  -backend-config="resource_group_name=<state-resource-group>" `
  -backend-config="storage_account_name=<state-storage-account>" `
  -backend-config="container_name=tfstate" `
  -backend-config="key=organic-ghee.tfstate"
```

Plan the development environment:

```powershell
terraform -chdir=terraform workspace select dev
terraform -chdir=terraform plan -var-file="environments/dev/terraform.tfvars"
```

Plan production with its public application domain:

```powershell
terraform -chdir=terraform workspace select prod
terraform -chdir=terraform plan `
  -var-file="environments/prod/terraform.tfvars" `
  -var="application_base_url=https://<production-domain>"
```

Production application deployment uses GitHub OIDC and a self-hosted runner
inside the production virtual network. The runner must carry the labels
`self-hosted`, `linux`, and `prod-vnet`.

## Documentation

- [Azure Deployment Runbook](docs/azure-deployment-runbook.md)
- [Terraform Deployment Flow](docs/terraform-deployment-flow.md)
- [Security Hardening Guide](docs/security-hardening-guide.md)
- [Disaster Recovery Guide](docs/disaster-recovery-guide.md)
