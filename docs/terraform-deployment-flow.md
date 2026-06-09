# Terraform Deployment Flow

**Purpose**

This document describes the exact end-to-end deployment lifecycle from an empty Azure subscription to a fully running production application using Infrastructure as Code (Terraform) and CI/CD (GitHub Actions).

**Scope**

- All infrastructure is deployed via Terraform (no manual Portal resource creation).
- GitHub Actions orchestrates Terraform operations via GitHub OIDC Federation.
- Application deployment follows infrastructure readiness.

---

## 1. Initial Azure Prerequisites

**What to verify before starting**

1. **Azure Subscription**
   - A single subscription or multiple subscriptions (one for platform/state, one for workloads).
   - Recommended: separate "platform" subscription for Terraform state backend to isolate critical infrastructure.
   - Subscription ID: `AZURE_SUBSCRIPTION_ID` — store this for later use.

2. **Entra Tenant**
   - Access to Microsoft Entra ID tenant where App Registrations will be created.
   - Tenant ID: `AZURE_TENANT_ID` — store this for later use.
   - Required permissions: `Cloud Application Administrator` or `Application Administrator` to create app registrations and federated credentials.

3. **GitHub Repository Access**
   - Repository admin access (to configure OIDC, secrets, branch protection, environments).
   - Default branch: `main` (protected with required PR reviews and status checks).
   - Organization: `<github-org>` — store this for later use.

4. **Local Environment**
   - Azure CLI: `az --version` (ensure >= 2.50)
   - Terraform: `terraform --version` (ensure >= 1.8)
   - Git: `git --version` (ensure >= 2.30)
   - Node.js (for local app builds if needed): `node --version` (>= 16)

**Pre-flight checklist**

```
✓ Azure subscription created and accessible
✓ Entra tenant identified (Tenant ID)
✓ GitHub repository created with default branch `main`
✓ Repository admin access confirmed
✓ Local CLI tools installed (az, terraform, git)
✓ Azure CLI authenticated: az login --use-device-code (if needed)
```

---

## 2. Bootstrap Phase

**Why Bootstrap Exists**

Terraform needs a secure, remote backend to store state. The backend itself cannot be managed by Terraform (chicken-and-egg problem). Bootstrap creates:
- A dedicated Resource Group for state infrastructure.
- A Storage Account with Blob versioning and soft-delete enabled.
- A private Blob Container for state files.
- Optionally, a resource lock to prevent accidental deletion.

**Bootstrap Deployment Steps**

### Step 2.1: Prepare Bootstrap Terraform

From the repository root:

```bash
cd terraform/backend
terraform init
```

This initializes Terraform in the `backend/` folder using local state (temporary, will be destroyed after bootstrap).

### Step 2.2: Create Bootstrap Resources

```bash
terraform apply
```

Expected output:
- `storage_account_name`: name of the state storage account (e.g., `tfstate1a2b3c4d`)
- `container_name`: name of the blob container (e.g., `tfstate`)
- Resource Group: `tfstate-rg`

**Record these values** — they are needed for configuring Terraform backend in the next phase.

### Step 2.3: Verify Bootstrap

```bash
# Verify storage account created
az storage account show --name <storage_account_name> --query "{name:name, tier:accessTier, enableVersioning:properties.encryption.services.blob.enabled}"

# Verify container exists
az storage container list --account-name <storage_account_name> --query "[].name"

# List blob versions (confirm versioning enabled)
az storage blob list --account-name <storage_account_name> --container-name tfstate --version-id "*"
```

### Step 2.4: Clean Up Local Bootstrap State

```bash
cd terraform/backend
rm -rf .terraform terraform.tfstate terraform.tfstate.backup
```

The local bootstrap state is no longer needed (it was only used to create the remote backend).

**State Locking**

The `azurerm` backend uses Azure Blob Lease to provide distributed locking. When `terraform apply` runs:
1. A lease is acquired on the state blob.
2. Operation executes.
3. Lease is released.

Only one operation can hold a lease at a time, preventing concurrent state modifications. Lease timeout is configurable (default 30s).

**State Recovery Strategy**

- The state storage account has versioning and soft-delete enabled.
- If state is corrupted: restore a previous version using `az storage blob show --name terraform.tfstate --version-id <version-id>`.
- If storage account is deleted: recover using soft-delete restoration within the retention window (default 7 days).
- For critical scenarios, implement nightly copies of state blobs to a secondary storage account in another region using Azure Storage replication or `az storage blob copy`.

---

## 3. GitHub OIDC Setup

**Why OIDC?**

OIDC (OpenID Connect) allows GitHub Actions to obtain short-lived Azure credentials without storing long-lived secrets. This eliminates the risk of leaked service principal credentials in GitHub.

**OIDC Flow Diagram**

```
GitHub Actions Job
  ↓ (requests token)
GitHub OIDC Provider
  ↓ (validates GitHub context)
Azure Entra ID
  ↓ (validates federated credential)
Token Issued (valid for job only, ~15 minutes)
  ↓
Terraform / Azure CLI uses token
  ↓
Job completes, token expires automatically
```

**Setup Steps**

### Step 3.1: Create Entra App Registration

Use Azure CLI or Portal.

```bash
# Create app registration for GitHub Actions
az ad app create --display-name "github-actions-terraform-<project>"

# Get the application ID (client ID)
APP_ID=$(az ad app list --query "[?displayName=='github-actions-terraform-<project>'].appId" -o tsv)
echo "Application ID: $APP_ID"

# Create service principal for the app
az ad sp create --id $APP_ID

# Get service principal object ID
SP_OBJECT_ID=$(az ad sp list --query "[?appId=='$APP_ID'].id" -o tsv)
echo "Service Principal Object ID: $SP_OBJECT_ID"
```

### Step 3.2: Configure Federated Credentials

Federated credentials allow GitHub Actions to authenticate without secrets.

```bash
# Add federated credential for GitHub (repository)
az identity federated-credential create \
  --resource-group <rg> \
  --identity-name <managed-identity> \
  --name "github-<org>-<repo>" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:<github-org>/<github-repo>:ref:refs/heads/main" \
  --audience "api://AzureADTokenExchange"
```

Alternatively, use the following steps if using App Registration directly:

```bash
# Create federated credential on App Registration
az ad app federated-credential create \
  --id $APP_ID \
  --parameters \
  '{
    "name": "github-main-branch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<github-org>/<github-repo>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### Step 3.3: Assign RBAC Roles

The service principal needs permissions to manage resources in the subscription.

```bash
# Assign Contributor role (or more granular roles like Owner, Terraform Executor)
az role assignment create \
  --assignee-object-id $SP_OBJECT_ID \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/<subscription-id>"
```

### Step 3.4: Configure GitHub Repository Secrets

In GitHub repository settings, add:

1. **Variables** (non-secret, used in workflows):
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_CLIENT_ID` (the App ID from step 3.1)

2. **Repository Environments** (for prod approvals):
   - Create environment: `production`
   - Add required reviewers (team leads, platform engineers)
   - Add secrets if service principal auth is used (not needed for OIDC):
     - `AZURE_CLIENT_SECRET` (only if not using OIDC)

### Step 3.5: Verify OIDC Configuration

Test the OIDC token from a GitHub Actions workflow (add a temporary test job):

```yaml
jobs:
  test-oidc:
    runs-on: ubuntu-latest
    steps:
      - name: Get OIDC token
        run: |
          curl -H "Authorization: bearer ${{ secrets.GITHUB_TOKEN }}" \
            "${{ env.ACTIONS_ID_TOKEN_REQUEST_URL }}?audience=api://AzureADTokenExchange" \
            -o token.json
          echo "Token obtained successfully"
```

If successful, the workflow logs will show token obtained. If OIDC fails, check:
- Federated credential subject matches GitHub context exactly (case-sensitive)
- App Registration has the federated credential attached
- Service principal has RBAC permissions on the subscription

---

## 4. Terraform Infrastructure Deployment

**Deployment Order**

```
┌─────────────────────────────────────────┐
│ Bootstrap Phase (Section 2)             │
│ - Remote state backend created          │
│ - Ready for main Terraform              │
└─────────────────────────┬───────────────┘
                          ↓
        ┌─────────────────────────────────┐
        │ Dev Infrastructure              │
        │ - terraform init (backend)      │
        │ - terraform workspace new dev   │
        │ - terraform plan                │
        │ - terraform apply               │
        └─────────────────────────┬───────┘
                                  ↓
                    ┌─────────────────────┐
                    │ Validation          │
                    │ - Smoke tests       │
                    │ - Health checks     │
                    └────────────┬────────┘
                                 ↓
                ┌────────────────────────────────┐
                │ Prod Infrastructure            │
                │ - terraform workspace new prod │
                │ - terraform plan               │
                │ - terraform apply (approval)   │
                └────────────────────────────────┘
```

### Step 4.1: Initialize Terraform with Remote Backend

From `terraform/` root:

```bash
cd terraform

# Initialize backend with remote state configuration
terraform init \
  -backend-config="resource_group_name=tfstate-rg" \
  -backend-config="storage_account_name=<storage_account_name_from_bootstrap>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=terraform.tfstate"
```

Expected output:
```
Terraform has been successfully configured!
```

Verify:
```bash
terraform state list
# Should be empty initially
```

### Step 4.2: Create Workspaces

Workspaces isolate state per environment:

```bash
# Create dev workspace
terraform workspace new dev

# Create prod workspace
terraform workspace new prod

# List workspaces
terraform workspace list
# Output:
# default
# * dev
# prod
```

### Step 4.3: Deploy Dev Infrastructure

Switch to dev workspace and validate:

```bash
terraform workspace select dev

# Validate Terraform configuration
terraform validate

# Format check
terraform fmt -check -recursive

# Create a plan
terraform plan -var-file="environments/dev/terraform.tfvars" -out=tfplan.dev
```

Review the plan output:
- Resource Group: `sapp-dev-rg`
- Storage Account: `sapp-devsa<suffix>`
- Key Vault: `sapp-dev-kv`
- App Service: `sapp-dev-appsvc`
- Entra App Registration: `sapp-dev-app`

If plan is acceptable, apply:

```bash
terraform apply tfplan.dev
```

Expected outputs:
```
resource_group_name = "sapp-dev-rg"
app_service_url = "sapp-dev-appsvc.azurewebsites.net"
storage_account_name = "sappdevsa<suffix>"
key_vault_name = "sapp-dev-kv"
entra_app_id = "<application-id-guid>"
```

**Save these outputs** — they are needed for validation and application deployment.

### Step 4.4: Deploy Prod Infrastructure

Switch to prod workspace:

```bash
terraform workspace select prod

terraform plan -var-file="environments/prod/terraform.tfvars" -out=tfplan.prod
```

Review the plan carefully — prod uses larger SKUs:
- App Service Plan: `Standard / S1` (vs. `Basic / B1` for dev)
- Storage Account: `Standard_ZRS` (vs. `Standard_LRS` for dev) — Zone-Redundant Replication for higher durability

Apply prod infrastructure:

```bash
terraform apply tfplan.prod
```

**Note:** For production, you should use GitHub Actions with an approval gate (see Step 4.5).

### Step 4.5: Terraform Operations in GitHub Actions

Workflows automatically:
1. Run `terraform fmt -check` to validate formatting.
2. Run `terraform validate` to check configuration syntax.
3. Run `terraform plan` and post results to PR.
4. On merge to `main`, run `terraform apply` (with approval for prod).

The workflow defines:
- `working-directory: terraform` to run commands in Terraform root.
- `OIDC_TOKEN` environment variable passed to `az` CLI, which authenticates using the federated credential.

**Local vs. CI Execution**

| Task | Local | CI/CD |
|------|-------|-------|
| `terraform init` | Yes (manual, one-time) | Yes (each job) |
| `terraform fmt/validate` | Yes (development) | Yes (PR check) |
| `terraform plan` | Yes (dev only) | Yes (PR + main branch) |
| `terraform apply` | Yes (dev only) | Yes (main with approval for prod) |

---

## 5. Infrastructure Validation

After `terraform apply` completes, verify all resources are healthy.

### Step 5.1: Verify Resource Group

```bash
az group show -n sapp-dev-rg -o json | jq "{name, location, provisioningState}"
```

Expected: `provisioningState: "Succeeded"`

### Step 5.2: Verify Storage Account

```bash
STORAGE_ACCT=$(terraform output -raw storage_account_name)

# Check storage account properties
az storage account show -n $STORAGE_ACCT -o json | jq "{name, sku.name, properties.encryption.services.blob.enabled}"

# Verify container exists
az storage container list --account-name $STORAGE_ACCT -o table
```

Expected:
- SKU: `Standard_LRS` (dev) or `Standard_ZRS` (prod)
- Blob encryption: `true`
- Container: `appblob`

### Step 5.3: Verify Key Vault

```bash
KV_NAME=$(terraform output -raw key_vault_name)

# Check Key Vault properties
az keyvault show -n $KV_NAME -o json | jq "{name, properties.enableSoftDelete, properties.enablePurgeProtection}"

# List secrets
az keyvault secret list --vault-name $KV_NAME -o table
```

Expected:
- Soft-delete enabled: `true`
- Secret containing client secret exists

### Step 5.4: Verify App Service

```bash
APP_NAME=$(terraform output -raw resource_group_name | sed 's/-rg//-appsvc/') # adjust parsing as needed
RG=$(terraform output -raw resource_group_name)

# Check App Service state
az webapp show -n $APP_NAME -g $RG -o json | jq "{name, state, defaultHostName, identity.type}"

# Check app settings
az webapp config appsettings list -n $APP_NAME -g $RG -o table
```

Expected:
- State: `Running`
- Identity type: `SystemAssigned`
- App settings include `KEY_VAULT_NAME`, `BLOB_CONTAINER`

### Step 5.5: Verify Entra Application

```bash
ENTRA_APP_ID=$(terraform output -raw entra_app_id)

# Check app registration
az ad app show --id $ENTRA_APP_ID -o json | jq "{appId, displayName, web.redirectUris}"
```

Expected:
- `displayName: "sapp-dev-app"` (or similar)
- `web.redirectUris` present (if configured)

### Step 5.6: Validate Managed Identity Access to Key Vault

The App Service's system-assigned Managed Identity should have `Key Vault Secrets User` RBAC role:

```bash
APP_PRINCIPAL_ID=$(az webapp identity show -g $RG -n $APP_NAME --query principalId -o tsv)

# List role assignments for the managed identity
az role assignment list --assignee-object-id $APP_PRINCIPAL_ID -o table
```

Expected: Role `Key Vault Secrets User` with scope set to the Key Vault.

### Validation Checklist

```
✓ Resource Group exists and is in region eastus
✓ Storage Account created with versioning and soft-delete enabled
✓ Blob Container is private
✓ Key Vault created with soft-delete enabled
✓ Key Vault has secret for Entra client secret
✓ App Service Plan created with appropriate SKU (B1 dev, S1 prod)
✓ Linux Web App created and running
✓ App Service has SystemAssigned Managed Identity
✓ App Service has Key Vault Secrets User RBAC
✓ Entra App Registration created with Client ID
✓ All resources tagged correctly (Environment, Project, Owner, CostCenter, ManagedBy)
```

---

## 6. Application Deployment Flow

**Application Deployment Sequence**

```
Developer commits and pushes
  ↓ (git push)
GitHub detects push to main
  ↓
Trigger CI workflow
  ↓ (GitHub Actions)
Build Node.js application
  ├─ npm ci (install dependencies)
  ├─ npm run build (if applicable)
  └─ npm run test (if applicable)
  ↓
Create artifact (ZIP package)
  ├─ Include dist/ (compiled output)
  ├─ Include node_modules/ (or rely on App Service remote build)
  └─ Package for deployment
  ↓
Deploy to App Service
  ├─ Authenticate via OIDC
  ├─ Upload ZIP to App Service
  └─ Trigger app restart / swap deployment slot
  ↓
Validate deployment
  ├─ Health check endpoint
  ├─ Verify app is responding
  └─ Check logs for startup errors
  ↓
Deployment complete
```

### Step 6.1: Build Process (Occurs in GitHub Actions)

The CI workflow triggers on push to `main`:

```yaml
# Conceptual steps (not full YAML)
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 18

      - name: Install dependencies
        run: npm ci

      - name: Build application
        run: npm run build  # or skip if no build step

      - name: Run tests
        run: npm test  # optional

      - name: Create deployment package
        run: |
          zip -r app.zip . -x ".git*" ".terraform*" "node_modules/*" "*.tfvars"

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: app-package
          path: app.zip
```

### Step 6.2: Deployment to App Service

Continuation of workflow:

```yaml
      - name: Deploy to App Service
        run: |
          az webapp deployment source config-zip \
            --resource-group ${{ needs.terraform.outputs.resource_group }} \
            --name ${{ needs.terraform.outputs.app_name }} \
            --src-path app.zip
```

This uploads the ZIP directly to App Service. App Service:
1. Unzips the package.
2. Runs `npm ci` (if `package.json` detected).
3. Starts the application.

Alternatively, use deployment slots for zero-downtime deployments:
1. Deploy to "staging" slot.
2. Run smoke tests.
3. Swap staging and production slots.

### Step 6.3: Application Readiness

For App Service to correctly start the application:

1. **Entry point must be defined** — either in `package.json` scripts (e.g., `"start": "node src/app.js"`) or in App Service startup command (App Service settings: **Configuration → General → Startup Command** = `node src/app.js`).

2. **Port binding** — the app must listen on the port specified by `PORT` environment variable (default `8080` on App Service).

3. **Connection strings and secrets** — app retrieves from:
   - App Service app settings (for non-sensitive values)
   - Key Vault via Managed Identity (for secrets)

---

## 7. Post-Deployment Validation

After application deployment, validate all components are operational.

### Step 7.1: Health Check

```bash
APP_URL=$(terraform output -raw app_service_url)

# Basic HTTP request
curl -I https://$APP_URL/

# Expected: HTTP 200 or redirect
```

If the app exposes a `/health` endpoint:

```bash
curl -v https://$APP_URL/health
```

Expected response: JSON with status (e.g., `{"status": "ok"}`).

### Step 7.2: Key Vault Access Validation

Verify the app can access secrets in Key Vault via Managed Identity:

1. **From the app itself** — add a debug endpoint that attempts to fetch a secret and returns status (for testing only, disable in production).
2. **From App Service console** (Kudu):
   - Navigate to `https://<app-name>.scm.azurewebsites.net/DebugConsole`
   - Run: `curl https://<key-vault-name>.vault.azure.net/secrets/<secret-name>?api-version=2016-10-01` (with bearer token)
   - Confirm HTTP 200 and secret value returned.

### Step 7.3: Storage Account Access

Verify app can access Storage Account (if the app reads/writes blobs):

```bash
# From app or via az CLI
STORAGE=$(terraform output -raw storage_account_name)
CONTAINER="appblob"

az storage blob list --account-name $STORAGE --container-name $CONTAINER -o table
```

### Step 7.4: Application Insights Integration

Verify Application Insights is collecting telemetry:

1. In Azure Portal, navigate to Application Insights resource.
2. Check **Live Metrics** — should show incoming requests in real-time.
3. Check **Failed Requests** — if any errors, drill down to investigate.

### Step 7.5: Authentication Flow (if Entra-integrated)

If the app uses Entra ID for authentication:

1. Open the app URL in a browser.
2. Initiate login → redirect to Entra login page.
3. After login → redirect back to app with authorization code.
4. App exchanges code for token → user is authenticated.

If CORS or redirect URIs are misconfigured, you'll see errors like:
- AADSTS650052: Invalid redirect URI.
- CORS policy errors.

**Fix:** Update Entra App Registration redirect URIs via Terraform (in `modules/entra-id/main.tf`).

### Post-Deployment Checklist

```
✓ App Service state: Running
✓ HTTP requests return 200 or expected status
✓ Health check endpoint (if exists) returns success
✓ Application logs appear in App Service log stream (az webapp log tail)
✓ Managed Identity successfully retrieves secrets from Key Vault
✓ Storage Account blobs are accessible (if applicable)
✓ Application Insights receives telemetry
✓ No startup errors in logs
✓ Database (MongoDB) connectivity verified (if applicable)
✓ Authentication (Entra) flow works end-to-end (if applicable)
```

---

## 8. Security Flow

This section explains how secrets, identities, and permissions are managed end-to-end without exposing credentials in code or logs.

### Secret Management Flow

```
┌────────────────────────────────────────────────────────┐
│ Terraform creates resources                            │
├────────────────────────────────────────────────────────┤
│ 1. Generates client secret for Entra App              │
│    (random_password resource)                         │
│ 2. Stores secret in Key Vault                         │
│    (azurerm_key_vault_secret resource)                │
│ 3. Assigns RBAC to App Service Managed Identity      │
└────────────────────────────────────────────────────────┘
                          ↓
┌────────────────────────────────────────────────────────┐
│ App Service (runtime)                                 │
├────────────────────────────────────────────────────────┤
│ 1. Uses System-Assigned Managed Identity              │
│ 2. Requests token from Azure Instance Metadata        │
│ 3. Uses token to authenticate to Key Vault            │
│ 4. Retrieves secrets without credentials in code      │
└────────────────────────────────────────────────────────┘
```

### OIDC for GitHub Actions

```
┌────────────────────────────────────────────────────────┐
│ GitHub Actions Job (Terraform Apply)                  │
├────────────────────────────────────────────────────────┤
│ 1. Job requests OIDC token from GitHub                │
│ 2. GitHub signs token with OIDC issuer key            │
│ 3. Job exchanges token for Azure access token         │
│    (via Entra federated credential)                   │
│ 4. Terraform uses access token for az CLI             │
│ 5. No long-lived secrets stored or used               │
└────────────────────────────────────────────────────────┘
```

### RBAC Role Assignments

All roles are managed by Terraform (least privilege):

```
GitHub Actions Service Principal
  ├─ Contributor (or granular Terraform-specific role)
  └─ Limited to subscription scope

App Service Managed Identity
  ├─ Key Vault Secrets User
  │  └─ Scope: Key Vault resource
  ├─ Storage Blob Data Contributor (if writing blobs)
  │  └─ Scope: Storage Account
  └─ Other roles as needed
```

### Secrets Path (No Hardcoding)

1. **Development phase**: Terraform generates secrets (e.g., client secret).
2. **Storage**: Secrets stored in Key Vault (encrypted at rest).
3. **Access**: App Service uses Managed Identity + RBAC to retrieve secrets at runtime.
4. **Code**: Application code **never contains secrets** — references Key Vault URIs or app settings pointing to Key Vault.
5. **Logs**: If secrets are logged, Key Vault automatically redacts sensitive values in audit logs.

### Validation

```bash
# Verify no secrets in code
git log --all -S "password" --oneline
git log --all -S "secret" --oneline

# Verify Managed Identity has RBAC
az role assignment list --assignee-object-id $(az webapp identity show -g <rg> -n <app> --query principalId -o tsv) -o table

# Verify OIDC federated credential exists
az ad app federated-credential list --id <app-id> -o json
```

---

## 9. Disaster Recovery Flow

This section outlines recovery procedures for infrastructure and state failures.

### Terraform State Recovery

**Scenario: State is corrupted or lost**

```
Current State (Corrupted)
  ↓
Detect corruption (terraform plan shows unexpected changes)
  ↓
Restore from backup
  ├─ Option A: Blob versioning (restore previous version)
  ├─ Option B: Secondary storage account copy
  └─ Option C: Manual state reconstruction (advanced)
  ↓
Replace corrupted state with backup
  ├─ terraform state push <backup-state.json>
  └─ terraform plan (verify no destructive changes)
  ↓
Apply reconciliation
  ├─ terraform apply (if needed)
  └─ Validate resources match state
```

**Recovery steps**

```bash
# 1. List blob versions in state storage
az storage blob list --account-name <tfstate-account> --container-name tfstate --include-versions

# 2. Identify good version (timestamp)
# 3. Download specific version
az storage blob download \
  --account-name <tfstate-account> \
  --container-name tfstate \
  --name terraform.tfstate \
  --version-id <good-version-id> \
  --file terraform.tfstate.backup

# 4. Restore state (in appropriate workspace)
terraform state push terraform.tfstate.backup

# 5. Verify state
terraform state list
terraform plan
```

### App Service Recovery

**Scenario: App Service is unavailable or misconfigured**

```
App Service Down
  ↓
Check logs (az webapp log tail)
  ├─ Startup errors? → Fix app code, re-deploy
  ├─ Configuration errors? → Check app settings, update Terraform
  └─ Infrastructure issue? → Re-apply Terraform
  ↓
Re-deploy application
  ├─ Trigger GitHub Actions workflow manually
  ├─ Or: az webapp deployment source config-zip
  └─ Application starts
  ↓
Validate
  ├─ Health check
  ├─ Logs
  └─ App responding to requests
```

### Key Vault Recovery

**Scenario: Key Vault accidentally deleted**

```
Key Vault Deleted
  ↓
Check soft-delete status (purge-protection enabled?)
  ├─ Yes → Soft-delete: recover using portal or CLI
  └─ No → Cannot recover; restore from backup
  ↓
Recover using soft-delete
  az keyvault recover --name <kv-name> --resource-group <rg>
  ↓
Restore secrets
  ├─ If Key Vault deleted within retention window (default 7 days):
  └─ Secrets also restored automatically
  ↓
Verify access
  ├─ Managed Identity can retrieve secrets
  └─ App Service functional
```

### Storage Account Recovery

**Scenario: Storage Account data corrupted or lost**

```
Storage Data Issue
  ↓
Check soft-delete and blob versioning
  ├─ Recover blob from soft-delete (< 7 days)
  │  az storage blob undelete --account-name <acc> --container-name <cont> --name <blob>
  ├─ Restore specific version
  │  az storage blob download --version-id <version-id>
  └─ No recovery available → restore from backup copy
  ↓
Replicate from backup storage account
  ├─ Copy blobs from DR storage to primary storage
  └─ Restore application state
```

### Complete Infrastructure Recovery (Terraform Reapply)

**Scenario: Multiple resources are in bad state or region disaster**

```
Disaster Occurs (Region down, resources deleted, etc.)
  ↓
Assess state
  ├─ terraform refresh (check current state vs. Azure)
  └─ terraform plan (identify missing or misconfigured resources)
  ↓
Recover state
  ├─ If state is available: no action needed
  └─ If state is lost: see Terraform State Recovery above
  ↓
Reapply infrastructure
  terraform apply
  ├─ Terraform detects missing resources and recreates them
  ├─ All data (secrets, configurations) restored from Key Vault
  └─ Application re-deployed
  ↓
Validate
  ├─ All resources running
  ├─ Connectivity to services confirmed
  └─ Application accessible
```

---

## 10. Production Release Flow

This section documents the end-to-end process for releasing changes to production.

### Release Process Diagram

```
┌──────────────────────────────────────────────────────────┐
│ Developer Creates Feature Branch                         │
│ Commits code changes                                     │
└──────────────────────────────────────┬───────────────────┘
                                       ↓
┌──────────────────────────────────────────────────────────┐
│ GitHub: Create Pull Request to main                      │
│ - Title, description, linked issues                      │
│ - Code review required                                   │
└──────────────────────────────────────┬───────────────────┘
                                       ↓
┌──────────────────────────────────────────────────────────┐
│ GitHub Actions: PR Checks (Automated)                    │
│ - terraform fmt -check (formatting)                      │
│ - terraform validate (syntax)                            │
│ - terraform plan (show proposed changes)                 │
│ - Post plan as PR comment                                │
└──────────────────────────────────────┬───────────────────┘
                                       ↓
┌──────────────────────────────────────────────────────────┐
│ Code Review (Manual)                                     │
│ - Platform engineer reviews plan                         │
│ - Reviews code changes                                   │
│ - Approves or requests changes                           │
└──────────────────────────────────────┬───────────────────┘
                                       ↓
┌──────────────────────────────────────────────────────────┐
│ Merge PR to main                                         │
│ - All checks must pass                                   │
│ - PR approved by reviewers                               │
└──────────────────────────────────────┬───────────────────┘
                                       ↓
┌──────────────────────────────────────────────────────────┐
│ GitHub Actions: Merge Workflow                           │
│ - terraform init (remote state)                          │
│ - terraform plan (final validation)                      │
│ - Post plan as commit                                    │
│ - Await manual approval (for prod)                       │
└──────────────────────────────────────┬───────────────────┘
                                       ↓
┌──────────────────────────────────────────────────────────┐
│ Manual Approval (GitHub Environments)                    │
│ - Required reviewer approves deployment                  │
│ - Approval sent from authorized user                     │
│ - Deployment proceeds                                    │
└──────────────────────────────────────┬───────────────────┘
                                       ↓
┌──────────────────────────────────────────────────────────┐
│ GitHub Actions: terraform apply (Infrastructure)         │
│ - terraform apply (using saved plan)                     │
│ - Resources created/updated                              │
│ - Outputs printed to logs                                │
└──────────────────────────────────────┬───────────────────┘
                                       ↓
┌──────────────────────────────────────────────────────────┐
│ GitHub Actions: Build & Deploy Application               │
│ - npm ci, npm run build                                  │
│ - Create deployment package                              │
│ - Deploy to App Service (az webapp deployment)           │
│ - Health checks                                          │
└──────────────────────────────────────┬───────────────────┘
                                       ↓
┌──────────────────────────────────────────────────────────┐
│ Validation (Automated)                                   │
│ - HTTP health check                                      │
│ - Application Insights telemetry                         │
│ - Error rate monitoring                                  │
│ - Logs checked for errors                                │
└──────────────────────────────────────┬───────────────────┘
                                       ↓
┌──────────────────────────────────────────────────────────┐
│ Production Deployment Complete                           │
│ - All changes in effect                                  │
│ - Monitoring active                                      │
│ - On-call team notified                                  │
└──────────────────────────────────────────────────────────┘
```

### Rollback Procedure

If post-deployment validation fails:

```
Deployment Failure Detected
  ↓
Assess severity
  ├─ Minor (can wait) → create incident, schedule fix
  └─ Critical (P1) → initiate immediate rollback
  ↓
Identify previous good commit
  ├─ Check GitHub commit history
  ├─ Find last successful deployment
  └─ Identify commit hash
  ↓
Create rollback branch
  git checkout <good-commit-hash> -b rollback/<reason>
  ↓
Force-push rollback to main (with approval)
  git push origin rollback/<reason> --force-with-lease
  ↓
GitHub Actions executes rollback workflow
  ├─ terraform apply (reverts infrastructure)
  ├─ Deploy previous app version
  └─ Validation runs
  ↓
Confirm successful rollback
  ├─ App is responsive
  ├─ Errors reduced
  ├─ Services stabilized
  └─ Incident documented
```

### Change Log

Maintain a change log for auditing:

```
Date        | Change Type    | Description              | Status
------------|----------------|--------------------------|--------
2024-01-15  | Infrastructure | Increase App Service SKU | Deployed
2024-01-14  | Application    | Fix authentication bug   | Deployed
2024-01-13  | Security       | Update Key Vault policy  | Rollback
```

---

## Appendices

### A. Environment Configuration Summary

| Aspect | Dev | Prod |
|--------|-----|------|
| **Terraform Workspace** | `dev` | `prod` |
| **Variables File** | `environments/dev/terraform.tfvars` | `environments/prod/terraform.tfvars` |
| **App Service SKU** | Basic / B1 | Standard / S1 |
| **Storage Replication** | LRS | ZRS or GRS |
| **Backup Frequency** | Daily | Hourly |
| **RBAC Scope** | Dev team | Ops/Platform team |
| **Approval Required** | No | Yes |

### B. Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| terraform plan shows `Error acquiring state lock` | Another operation is using state | Wait for lease timeout (30s) or check for stuck operations |
| App Service fails to start | Startup command missing | Set Startup Command in App Service configuration |
| Managed Identity cannot access Key Vault | RBAC role not assigned | Run role assignment CLI command (see Section 8) |
| OIDC token acquisition fails | Federated credential mismatch | Verify subject matches exactly (case-sensitive) |
| Application Insights shows no data | App not instrumented | Add Application Insights SDK to app code |

### C. Related Documents

- [Security Hardening Guide](security-hardening-guide.md)
- [Monitoring Guide](monitoring-guide.md)
- [Disaster Recovery Guide](disaster-recovery-guide.md)
- [Production Readiness Review](production-readiness-review.md)
