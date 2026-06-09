# Security Hardening Guide

Purpose
- Prescribe secure defaults and operational steps to harden the Azure deployment.

1. Identity and Access Management
- Use GitHub OIDC federation for short-lived credentials in CI (preferred) — avoid storing long-lived secrets in GitHub.
- Entra App registration: follow least-privilege principles. Use separate App Registrations for platform operations and workload application.
- Assign RBAC roles to principals (Managed Identities, Service Principals) using built-in roles where possible (`Key Vault Secrets User`, `Storage Blob Data Contributor`, `Reader`).

Portal steps for RBAC (Key Vault secret access to managed identity)
- Portal navigation: Key Vaults -> Select your KV -> Access control (IAM) -> + Add role assignment -> Role: `Key Vault Secrets User` -> Assign access to: `Managed identity` -> Select the App Service's system-assigned identity -> Save.

2. Key Vault best practices
- Prefer RBAC model over Access Policies for scalable, auditable assignments.
- Enable soft-delete and purge-protection on Key Vault for protection against accidental or malicious deletion.
- Enable purge protection only after you are confident in retention behavior (it prevents permanent deletion until protection removed and is irreversible for a configured period).

3. Network and Perimeter
- Use Private Endpoints for Key Vault and Storage Account where possible.
- Restrict Storage Account and App Service access via service endpoints, private endpoints, or firewall rules.
- If App Service needs to access private resources, configure VNet integration and use service endpoints/private endpoints for resource access.

4. Secrets management
- Do not store secrets in code or in `terraform.tfvars` under source control.
- Use Key Vault for secrets and store secret URIs or Key Vault references in App Service configuration.
- App Service should use Managed Identity to retrieve secrets at runtime; alternatively use Key Vault references in App Settings: `@Microsoft.KeyVault(SecretUri=<secretUri>)`.

5. CI/CD hardening
- Use GitHub environments with required reviewers and protected secrets.
- Configure required branch protections and require PR reviews, signed commits, and vulnerability scanning via Dependabot.
- Limit who can approve `prod` deployments (environment protection rules).

6. Logging, auditing and policy
- Enable diagnostic settings to stream Key Vault logs and Storage logs to Log Analytics and an Event Hub for SIEM ingestion.
- Use Azure Policy to enforce secure configurations (e.g., enforce Key Vault soft-delete, enforce HTTPS-only for storage accounts, enforce TLS version >= 1.2).

7. Platform security checks
- Run Microsoft Defender for Cloud recommendations and track prioritized security alerts.

8. Recovery and credential rotation
- Rotate service principal credentials periodically and prefer OIDC for CI.
- Rotate Key Vault secrets and maintain secret rotation processes with monitoring.

9. Example CLI snippets
```bash
# Assign Key Vault Secrets User role to App Service identity
APP_PRINCIPAL_ID=$(az webapp identity show -g <rg> -n <app> --query principalId -o tsv)
az role assignment create --assignee-object-id $APP_PRINCIPAL_ID --assignee-principal-type ServicePrincipal --role "Key Vault Secrets User" --scope $(az keyvault show -n <kv> --query id -o tsv)
```

10. Recommended security checks
- Azure Security Center / Defender for Cloud: ensure subscription secure score > 80%.
- Periodic penetration testing and code dependency scanning.
