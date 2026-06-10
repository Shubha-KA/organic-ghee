# Organic Ghee Complete Deployment Guide

This runbook deploys the Organic Ghee platform from an empty Azure subscription
and a checked-out repository. Run the sections in order. Commands use
PowerShell 7 and Azure CLI unless stated otherwise.

## Deployment Facts

- Repository: `Shubha-KA/organic-ghee`
- Terraform root: `terraform/`
- Backend bootstrap root: `terraform/backend/`
- Terraform version used by GitHub Actions: `1.8.5`
- Dev workspace: `dev`
- Prod workspace: `prod`
- Dev resource group: `sapp-dev-rg`
- Prod resource group: `sapp-prod-rg`
- Dev App Service: `sapp-dev-appsvc`
- Prod App Service: `sapp-prod-appsvc`
- Prod Function App: `sapp-prod-notifications-func`
- Prod Front Door profile: `sapp-prod-afd`
- Prod Front Door endpoint: `sapp-prod-endpoint`
- Queue: `order-notifications`

Two prerequisites are not created by the current Terraform:

1. Dev requires an external MongoDB-compatible connection string because
   `enable_cosmos_db = false` in the Dev tfvars.
2. The production deployment runner requires a dedicated VM subnet. The
   Terraform VNet currently manages only the App Service integration subnet and
   private endpoint subnet. Section 4 creates the runner subnet and VM as
   explicitly documented operational resources.

Never commit state, plan files, database connection strings, runner tokens, or
other credentials.

## Workstation Variables

Open PowerShell from the repository root and set these values:

```powershell
$SubscriptionId = "<azure-subscription-id>"
$TenantId = "<microsoft-entra-tenant-id>"
$Location = "eastus"
$RepoOwner = "Shubha-KA"
$RepoName = "organic-ghee"
$ProdHostName = "www.example.com"
$ProdBaseUrl = "https://$ProdHostName"
$AdminUserUpns = @("admin@example.com")
$NotificationSender = "notifications@example.com"
$ContactRecipient = "orders@example.com"
$DevMongoConnectionString = "<mongodb-connection-string>"

$StateResourceGroup = "tfstate-rg"
$StateContainer = "tfstate"
$DevResourceGroup = "sapp-dev-rg"
$ProdResourceGroup = "sapp-prod-rg"
$DevWebApp = "sapp-dev-appsvc"
$ProdWebApp = "sapp-prod-appsvc"
$ProdFunctionApp = "sapp-prod-notifications-func"
$DevKeyVault = "sapp-dev-kv"
$ProdKeyVaultName = "sapp-prod-kv"
$ProdVnet = "sapp-prod-vnet"
$FrontDoorProfile = "sapp-prod-afd"
$FrontDoorEndpoint = "sapp-prod-endpoint"
```

Confirm that the repository root contains `package.json`, `terraform`, and
`.github`:

```powershell
Get-ChildItem package.json, terraform, .github
```

Expected: all three paths are returned.

# 1. Azure Preparation

## 1.1 Install and verify tools

Install:

- Azure CLI
- Terraform 1.8 or later
- Git
- Node.js 20
- GitHub CLI, recommended for environment configuration and workflow dispatch

Verify:

```powershell
az version
terraform version
git --version
node --version
gh --version
```

Expected:

- Azure CLI returns a JSON version document.
- Terraform reports `v1.8.x` or newer.
- Node reports `v20.x` or a compatible later LTS release.

## 1.2 Sign in and select the subscription

```powershell
az login --tenant $TenantId
az account set --subscription $SubscriptionId
az account show --query "{subscription:name, subscriptionId:id, tenantId:tenantId, state:state}" -o table
```

Expected:

- `subscriptionId` matches `$SubscriptionId`.
- `tenantId` matches `$TenantId`.
- `state` is `Enabled`.

## 1.3 Required Azure roles

The engineer performing the first local deployment needs either:

- `Owner` on the subscription; or
- `Contributor` plus `User Access Administrator` on the subscription.

These permissions are required because Terraform creates resources and RBAC
assignments.

Verify the current signed-in object and role assignments:

```powershell
$SignedInObjectId = az ad signed-in-user show --query id -o tsv
$SubscriptionScope = "/subscriptions/$SubscriptionId"

az role assignment list `
  --assignee-object-id $SignedInObjectId `
  --scope $SubscriptionScope `
  --include-inherited `
  --query "[].{Role:roleDefinitionName,Scope:scope}" `
  -o table
```

Expected: `Owner`, or both `Contributor` and `User Access Administrator`, at
the subscription or an inherited parent scope.

If a subscription Owner must grant the roles:

```powershell
az role assignment create `
  --assignee-object-id $SignedInObjectId `
  --assignee-principal-type User `
  --role "Contributor" `
  --scope $SubscriptionScope

az role assignment create `
  --assignee-object-id $SignedInObjectId `
  --assignee-principal-type User `
  --role "User Access Administrator" `
  --scope $SubscriptionScope
```

## 1.4 Required Microsoft Entra roles

The first deployment creates application registrations, service principals,
federated credentials, application passwords, app roles, and app-role
assignments. The signed-in engineer needs:

- `Cloud Application Administrator` or `Application Administrator`
- Permission to assign the `Admin` app role to the selected users or groups

A Privileged Role Administrator should activate or assign the role through
Microsoft Entra ID. Verify in the portal:

`Microsoft Entra ID > Roles and administrators > My roles`

The deployment will fail in the `azuread` provider with an authorization error
if these directory permissions are missing.

## 1.5 Register Azure resource providers

Register every provider used by the Terraform modules:

```powershell
$Providers = @(
  "Microsoft.Authorization",
  "Microsoft.Cdn",
  "Microsoft.DocumentDB",
  "Microsoft.Insights",
  "Microsoft.KeyVault",
  "Microsoft.ManagedIdentity",
  "Microsoft.Network",
  "Microsoft.OperationalInsights",
  "Microsoft.Resources",
  "Microsoft.Storage",
  "Microsoft.Web"
)

foreach ($Provider in $Providers) {
  az provider register --namespace $Provider
}
```

Registration is asynchronous. Wait until all providers report `Registered`:

```powershell
do {
  $ProviderStates = foreach ($Provider in $Providers) {
    az provider show `
      --namespace $Provider `
      --query "{Namespace:namespace,State:registrationState}" `
      -o json | ConvertFrom-Json
  }

  $ProviderStates | Format-Table
  $Pending = $ProviderStates | Where-Object State -ne "Registered"
  if ($Pending) { Start-Sleep -Seconds 15 }
} while ($Pending)
```

Expected: every provider has `State = Registered`.

## 1.6 Confirm subscription quota

Dev uses Linux App Service F1 in Australia East. Prod uses App Service P1v3,
Function EP1, Cosmos DB, Front Door Premium, private endpoints, and monitoring.
Confirm subscription offers and quotas before Prod:

```powershell
az vm list-usage --location eastus -o table
az appservice list-locations --sku P1v3 -o table
az appservice list-locations --sku F1 -o table
```

Stop if the required SKU is unavailable or the subscription has a zero quota
for paid production resources.

# 2. Domain Preparation

## 2.1 Purchase and manage the domain

Use a registrar and DNS provider that supports:

- TXT records
- CNAME records
- Low TTL values during cutover
- Programmatic or timely record changes
- CAA records that permit Microsoft-managed certificate issuance, if CAA is
  enabled

Use a subdomain such as `www.example.com`. A subdomain supports a normal CNAME.
An apex domain requires provider-specific ALIAS, ANAME, or CNAME-flattening
support and is not used in the examples below.

Do not point production traffic anywhere yet.

## 2.2 Predeployment DNS record plan

Terraform creates the Front Door custom-domain resource using
`$ProdHostName`. Azure then returns the unique TXT validation token and Front
Door endpoint hostname.

The records eventually required are:

| Type | Name | Value | Purpose |
| --- | --- | --- | --- |
| TXT | `_dnsauth.www` | Token returned by Azure Front Door | Domain ownership validation |
| CNAME | `www` | Front Door endpoint hostname ending in `azurefd.net` | Production traffic |

For `app.example.com`, use `_dnsauth.app` and `app`. For a provider that expects
the fully qualified record name, enter `_dnsauth.www.example.com` and
`www.example.com`.

Set the initial TTL to `300` seconds.

## 2.3 Verify current DNS before deployment

```powershell
Resolve-DnsName -Name $ProdHostName -ErrorAction SilentlyContinue
Resolve-DnsName -Name "_dnsauth.$ProdHostName" -Type TXT -ErrorAction SilentlyContinue
```

Expected before setup: no production Front Door CNAME and no stale validation
TXT record.

# 3. GitHub Preparation

## 3.1 Create GitHub environments

In the repository:

1. Open `Settings > Environments`.
2. Create `dev`.
3. Create `prod`.
4. Add required reviewers to `prod`.
5. Restrict `prod` deployment branches to `main`.
6. Optionally add a wait timer.

The environment names are case-sensitive because the federated subjects are:

```text
repo:Shubha-KA/organic-ghee:environment:dev
repo:Shubha-KA/organic-ghee:environment:prod
```

Terraform creates these federated credentials during the first local applies.

## 3.2 Required GitHub environment variables

Configure these variables separately in both `dev` and `prod`:

| Variable | Dev example | Prod example |
| --- | --- | --- |
| `AZURE_CLIENT_ID` | Dev `deployment_entra_client_id` output | Prod `deployment_entra_client_id` output |
| `AZURE_TENANT_ID` | `$TenantId` | `$TenantId` |
| `AZURE_SUBSCRIPTION_ID` | `$SubscriptionId` | `$SubscriptionId` |
| `AZURE_RESOURCE_GROUP` | `sapp-dev-rg` | `sapp-prod-rg` |
| `AZURE_WEBAPP_NAME` | `sapp-dev-appsvc` | `sapp-prod-appsvc` |
| `AZURE_FUNCTIONAPP_NAME` | Not set | `sapp-prod-notifications-func` |
| `TFSTATE_RESOURCE_GROUP` | `tfstate-rg` | `tfstate-rg` |
| `TFSTATE_STORAGE_ACCOUNT` | Backend output | Backend output |
| `TFSTATE_CONTAINER` | `tfstate` | `tfstate` |
| `APPLICATION_BASE_URL` | Dev App Service URL | `https://www.example.com` |

Configure this environment secret:

| Secret | Dev | Prod |
| --- | --- | --- |
| `DATABASE_CONNECTION_STRING` | Required external MongoDB connection string | Not required when Terraform-managed Cosmos DB is enabled |

Do not create `AZURE_CLIENT_SECRET`, `AZURE_CREDENTIALS`, or publish-profile
secrets. The workflows use GitHub OIDC only.

## 3.3 Configure with GitHub CLI

Authenticate:

```powershell
gh auth login
gh repo set-default "$RepoOwner/$RepoName"
```

After Sections 5, 6, and 8 produce the IDs, run:

```powershell
gh variable set AZURE_TENANT_ID --env dev --body $TenantId
gh variable set AZURE_SUBSCRIPTION_ID --env dev --body $SubscriptionId
gh variable set AZURE_RESOURCE_GROUP --env dev --body $DevResourceGroup
gh variable set AZURE_WEBAPP_NAME --env dev --body $DevWebApp
gh variable set TFSTATE_RESOURCE_GROUP --env dev --body $StateResourceGroup
gh variable set TFSTATE_STORAGE_ACCOUNT --env dev --body $StateStorageAccount
gh variable set TFSTATE_CONTAINER --env dev --body $StateContainer
gh variable set APPLICATION_BASE_URL --env dev --body $DevAppUrl
gh secret set DATABASE_CONNECTION_STRING --env dev --body $DevMongoConnectionString

gh variable set AZURE_TENANT_ID --env prod --body $TenantId
gh variable set AZURE_SUBSCRIPTION_ID --env prod --body $SubscriptionId
gh variable set AZURE_RESOURCE_GROUP --env prod --body $ProdResourceGroup
gh variable set AZURE_WEBAPP_NAME --env prod --body $ProdWebApp
gh variable set AZURE_FUNCTIONAPP_NAME --env prod --body $ProdFunctionApp
gh variable set TFSTATE_RESOURCE_GROUP --env prod --body $StateResourceGroup
gh variable set TFSTATE_STORAGE_ACCOUNT --env prod --body $StateStorageAccount
gh variable set TFSTATE_CONTAINER --env prod --body $StateContainer
gh variable set APPLICATION_BASE_URL --env prod --body $ProdBaseUrl
```

Set the client IDs after each environment apply:

```powershell
gh variable set AZURE_CLIENT_ID --env dev --body $DevDeploymentClientId
gh variable set AZURE_CLIENT_ID --env prod --body $ProdDeploymentClientId
```

Verify:

```powershell
gh variable list --env dev
gh variable list --env prod
gh secret list --env dev
gh secret list --env prod
```

Expected: all listed variables exist; Dev lists
`DATABASE_CONNECTION_STRING`; no long-lived Azure credential secret exists.

# 4. Self-Hosted Production Runner

## 4.1 Why the runner is required

Production disables public access to the App Service and Function App. Their
SCM/Kudu endpoints resolve through `privatelink.azurewebsites.net`. A
GitHub-hosted runner cannot reach those private endpoints. The workflow
therefore targets:

```text
self-hosted, linux, prod-vnet
```

Create the runner only after the Prod infrastructure and private DNS zones
exist.

Execution gate: read this section during preparation, but execute Sections
4.2 through 4.6 immediately after Section 8.7. Then continue with Section 9.

## 4.2 Create a dedicated runner subnet

Do not place the VM in `snet-app-integration`; it is delegated to App Service.
Do not place it in `snet-private-endpoints`. Create a dedicated subnet:

```powershell
$RunnerSubnet = "snet-prod-runner"
$RunnerSubnetPrefix = "10.20.3.0/27"
$RunnerNsg = "sapp-prod-runner-nsg"
$RunnerVm = "sapp-prod-gh-runner-01"
$RunnerAdmin = "azureadmin"
$EngineerPublicIp = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()

az network nsg create `
  --resource-group $ProdResourceGroup `
  --name $RunnerNsg `
  --location $Location

az network nsg rule create `
  --resource-group $ProdResourceGroup `
  --nsg-name $RunnerNsg `
  --name AllowSshFromEngineer `
  --priority 100 `
  --direction Inbound `
  --access Allow `
  --protocol Tcp `
  --source-address-prefixes "$EngineerPublicIp/32" `
  --destination-port-ranges 22

az network vnet subnet create `
  --resource-group $ProdResourceGroup `
  --vnet-name $ProdVnet `
  --name $RunnerSubnet `
  --address-prefixes $RunnerSubnetPrefix `
  --network-security-group $RunnerNsg
```

The current Terraform does not manage this subnet, NSG, or VM. Record them in
the operations inventory and do not import them without an approved Terraform
change.

## 4.3 Create the VM

This bootstrap method creates a public IP restricted to the engineer's current
address. For a mature landing zone, replace this with Azure Bastion and
explicit outbound connectivity.

```powershell
az vm create `
  --resource-group $ProdResourceGroup `
  --name $RunnerVm `
  --image Ubuntu2204 `
  --size Standard_B2s `
  --admin-username $RunnerAdmin `
  --generate-ssh-keys `
  --vnet-name $ProdVnet `
  --subnet $RunnerSubnet `
  --public-ip-sku Standard `
  --nsg $RunnerNsg
```

Expected: JSON containing `powerState = VM running` and a public IP address.

```powershell
$RunnerIp = az vm show `
  --resource-group $ProdResourceGroup `
  --name $RunnerVm `
  --show-details `
  --query publicIps `
  -o tsv

ssh "$RunnerAdmin@$RunnerIp"
```

## 4.4 Install dependencies on the VM

Run on the VM:

```bash
sudo apt-get update
sudo apt-get install -y curl git jq unzip zip dnsutils

curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

wget -qO- https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update
sudo apt-get install -y terraform
sudo snap install powershell --classic

az version
terraform version
pwsh --version
```

## 4.5 Register the GitHub runner

In GitHub, open:

`Settings > Actions > Runners > New self-hosted runner > Linux > x64`

GitHub displays a time-limited download URL and registration token. Run the
displayed download commands on the VM, then configure:

```bash
mkdir -p ~/actions-runner
cd ~/actions-runner

# Run the exact curl and tar commands shown by GitHub for the current runner release.

./config.sh \
  --url https://github.com/Shubha-KA/organic-ghee \
  --token '<time-limited-registration-token>' \
  --name sapp-prod-gh-runner-01 \
  --labels prod-vnet \
  --work _work \
  --unattended \
  --replace

sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

GitHub automatically adds `self-hosted`, `Linux`, and `X64`; the command adds
`prod-vnet`. Label matching is case-insensitive, but the workflow expects
`self-hosted`, `linux`, and `prod-vnet`.

## 4.6 Verify private resolution and runner health

Run on the VM:

```bash
getent ahostsv4 sapp-prod-appsvc.scm.azurewebsites.net
getent ahostsv4 sapp-prod-notifications-func.scm.azurewebsites.net
```

Expected: the first returned address is in the VNet private address range,
normally `10.20.2.0/27`.

In GitHub, verify the runner state is `Idle` under
`Settings > Actions > Runners`.

# 5. Terraform Backend

## 5.1 Initialize and apply the backend bootstrap

From the repository root:

```powershell
terraform -chdir=terraform/backend init
terraform -chdir=terraform/backend fmt -check
terraform -chdir=terraform/backend validate
terraform -chdir=terraform/backend plan `
  -var="state_blob_data_contributor_principal_id=$SignedInObjectId" `
  -out=tfbackend.plan
terraform -chdir=terraform/backend apply tfbackend.plan
```

Expected apply summary:

```text
Apply complete! Resources: <n> added, 0 changed, 0 destroyed.
```

The exact count can change with provider behavior. The required resources are:

- `tfstate-rg`
- Standard LRS Storage Account with a generated globally unique name
- Private `tfstate` blob container
- `Storage Blob Data Contributor` for the bootstrap engineer
- `CanNotDelete` resource-group lock

Capture outputs:

```powershell
$StateStorageAccount = terraform -chdir=terraform/backend output -raw storage_account_name
$StateContainer = terraform -chdir=terraform/backend output -raw container_name

$StateStorageAccount
$StateContainer
```

Expected: an account beginning with `tfstate` and container `tfstate`.

## 5.2 Verify state protection

```powershell
az storage account show `
  --resource-group $StateResourceGroup `
  --name $StateStorageAccount `
  --query "{HttpsOnly:enableHttpsTrafficOnly,TLS:minimumTlsVersion,PublicBlobAccess:allowBlobPublicAccess}" `
  -o table

az storage account blob-service-properties show `
  --resource-group $StateResourceGroup `
  --account-name $StateStorageAccount `
  --query "{Versioning:isVersioningEnabled,BlobDeleteDays:deleteRetentionPolicy.days,ContainerDeleteDays:containerDeleteRetentionPolicy.days}" `
  -o table

az lock list `
  --resource-group $StateResourceGroup `
  --query "[].{Name:name,Level:level}" `
  -o table
```

Expected:

- HTTPS only: `true`
- TLS: `TLS1_2`
- Public blob access: `false`
- Versioning: `true`
- Blob and container retention: `30`
- Lock level: `CanNotDelete`

Azure Blob leases provide state locking. A concurrent Terraform operation
should fail to acquire the lease rather than write state simultaneously.

Wait up to five minutes for the data-plane role assignment to propagate before
initializing the main backend.

## 5.3 Initialize the main Terraform backend

```powershell
terraform -chdir=terraform init -reconfigure `
  -backend-config="resource_group_name=$StateResourceGroup" `
  -backend-config="storage_account_name=$StateStorageAccount" `
  -backend-config="container_name=$StateContainer" `
  -backend-config="key=terraform.tfstate"
```

Expected:

```text
Terraform has been successfully initialized!
```

# 6. Dev Deployment

## 6.1 Prepare the Dev database secret

Dev does not create Cosmos DB. Obtain a valid MongoDB-compatible connection
string from an approved external database service. Restrict network access and
create a dedicated least-privilege application database user.

Set it only in the current shell:

```powershell
$env:TF_VAR_database_connection_string = $DevMongoConnectionString
```

## 6.2 Select or create the Dev workspace

```powershell
terraform -chdir=terraform workspace select dev
if ($LASTEXITCODE -ne 0) {
  terraform -chdir=terraform workspace new dev
}

terraform -chdir=terraform workspace show
```

Expected: `dev`.

## 6.3 Validate and create the first-stage foundation

```powershell
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate

terraform -chdir=terraform plan `
  -var-file="environments/dev/terraform.tfvars" `
  -target=module.resource_group `
  -target=module.storage `
  -target=module.entra `
  -target=module.key_vault `
  -out="dev-foundation.tfplan"

terraform -chdir=terraform apply "dev-foundation.tfplan"
```

Terraform warns that resource targeting is active. This is intentional only
for the first deployment: it creates the RBAC-enabled Key Vault before secret
resources are attempted.

Grant the signed-in engineer Key Vault data-plane access:

```powershell
$DevKeyVaultId = az keyvault show `
  --resource-group $DevResourceGroup `
  --name $DevKeyVault `
  --query id `
  -o tsv

az role assignment create `
  --assignee-object-id $SignedInObjectId `
  --assignee-principal-type User `
  --role "Key Vault Secrets Officer" `
  --scope $DevKeyVaultId
```

Wait up to five minutes for RBAC propagation.

## 6.4 Create and review the complete Dev plan

```powershell
terraform -chdir=terraform plan `
  -var-file="environments/dev/terraform.tfvars" `
  -out="dev.tfplan"
```

Review the plan. Dev should create:

- Resource group
- Linux App Service Plan F1 in Australia East
- Linux App Service
- Storage Account Standard LRS
- Private blob container `appblob`
- Queue `order-notifications`
- Key Vault
- Session and application secrets
- Entra deployment application and service principal
- Dev and Prod GitHub federated credentials
- Entra admin application registration and service principal
- Managed identities and RBAC assignments

Dev should not create:

- Front Door or WAF
- VNet or private endpoints
- Cosmos DB
- Function App
- Application Insights or Log Analytics
- Production resource locks

Stop if the plan contains destroys or paid production resources.

## 6.5 Apply Dev

```powershell
terraform -chdir=terraform apply "dev.tfplan"
```

Expected:

```text
Apply complete! Resources: <n> added, 0 changed, 0 destroyed.
```

Capture outputs:

```powershell
$DevAppUrl = terraform -chdir=terraform output -raw app_service_url
$DevDeploymentClientId = terraform -chdir=terraform output -raw deployment_entra_client_id
$DevAdminClientId = terraform -chdir=terraform output -raw admin_entra_client_id

terraform -chdir=terraform output
```

## 6.6 Grant Dev OIDC identity backend access

The workload Terraform grants the deployment identity access to the workload
resource group, but the backend is separate. Assign backend data access:

```powershell
$DevDeploymentSpObjectId = az ad sp show `
  --id $DevDeploymentClientId `
  --query id `
  -o tsv

$StateStorageId = az storage account show `
  --resource-group $StateResourceGroup `
  --name $StateStorageAccount `
  --query id `
  -o tsv

az role assignment create `
  --assignee-object-id $DevDeploymentSpObjectId `
  --assignee-principal-type ServicePrincipal `
  --role "Storage Blob Data Contributor" `
  --scope $StateStorageId

az role assignment create `
  --assignee-object-id $DevDeploymentSpObjectId `
  --assignee-principal-type ServicePrincipal `
  --role "Reader" `
  --scope $StateStorageId
```

RBAC can take several minutes to propagate.

## 6.7 Validate Dev infrastructure

```powershell
az group show --name $DevResourceGroup --query properties.provisioningState -o tsv

az webapp show `
  --resource-group $DevResourceGroup `
  --name $DevWebApp `
  --query "{State:state,HttpsOnly:httpsOnly,PublicAccess:publicNetworkAccess,Host:defaultHostName}" `
  -o table

az appservice plan show `
  --resource-group $DevResourceGroup `
  --name "$DevWebApp-plan" `
  --query "{Sku:sku.name,Tier:sku.tier,Kind:kind}" `
  -o table
```

Expected:

- Resource group state: `Succeeded`
- Web App state: `Running`
- HTTPS only: `true`
- Dev public access: enabled
- SKU: `F1`

Before application deployment, `/health` may not return a valid application
response.

## 6.8 Dev troubleshooting

- `Operation cannot be completed without additional quota`: confirm F1 is
  available in Australia East and the plan location is `australiaeast`.
- `Authorization_RequestDenied`: activate the required Entra directory role.
- `RoleAssignmentExists`: import or reconcile the existing assignment; do not
  delete blindly.
- `KeyVault` 403 during secret creation: wait for RBAC propagation and rerun
  the same plan.
- Backend 403: confirm `Storage Blob Data Contributor` on the backend account.
- Mongo connection failure: verify the connection string, database allowlist,
  credentials, and TLS requirements.

# 7. Dev Application Deployment

## 7.1 Configure the Dev GitHub environment

Complete Section 3 with:

```powershell
gh variable set AZURE_CLIENT_ID --env dev --body $DevDeploymentClientId
gh variable set AZURE_TENANT_ID --env dev --body $TenantId
gh variable set AZURE_SUBSCRIPTION_ID --env dev --body $SubscriptionId
gh variable set AZURE_RESOURCE_GROUP --env dev --body $DevResourceGroup
gh variable set AZURE_WEBAPP_NAME --env dev --body $DevWebApp
gh variable set TFSTATE_RESOURCE_GROUP --env dev --body $StateResourceGroup
gh variable set TFSTATE_STORAGE_ACCOUNT --env dev --body $StateStorageAccount
gh variable set TFSTATE_CONTAINER --env dev --body $StateContainer
gh variable set APPLICATION_BASE_URL --env dev --body $DevAppUrl
gh secret set DATABASE_CONNECTION_STRING --env dev --body $DevMongoConnectionString
```

## 7.2 Verify OIDC federation

```powershell
$DevAppObjectId = az ad app show --id $DevDeploymentClientId --query id -o tsv

az rest `
  --method GET `
  --uri "https://graph.microsoft.com/v1.0/applications/$DevAppObjectId/federatedIdentityCredentials" `
  --query "value[].{Name:name,Subject:subject,Audience:audiences[0]}" `
  -o table
```

Expected subjects include:

```text
repo:Shubha-KA/organic-ghee:environment:dev
repo:Shubha-KA/organic-ghee:environment:prod
```

## 7.3 Run the application workflow

In GitHub:

1. Open `Actions`.
2. Select `Deploy application`.
3. Select `Run workflow`.
4. Branch: `main`.
5. Environment: `dev`.
6. Select `Run workflow`.

Or:

```powershell
gh workflow run "Deploy application" --ref main -f environment=dev
gh run list --workflow "Deploy application" --limit 5
```

Expected jobs:

- `build`: succeeds
- `deploy-dev`: succeeds
- `deploy-prod`: skipped

The workflow uses `azure/login@v2` with OIDC, builds the Node.js package, and
uses ZIP deployment. No publish profile is used.

## 7.4 Validate Dev application

```powershell
Invoke-RestMethod "$DevAppUrl/health"
Invoke-WebRequest "$DevAppUrl/" -UseBasicParsing | Select-Object StatusCode
```

Expected:

- `/health`: HTTP 200 with `{"status":"healthy"}`
- `/`: HTTP 200

If `/health` returns 503, inspect:

```powershell
az webapp log tail --resource-group $DevResourceGroup --name $DevWebApp
az webapp config appsettings list --resource-group $DevResourceGroup --name $DevWebApp -o table
```

Do not print Key Vault secret values.

# 8. Prod Deployment

## 8.1 Resolve administrator object IDs

```powershell
$AdminObjectIds = @(
  foreach ($Upn in $AdminUserUpns) {
    az ad user show --id $Upn --query id -o tsv
  }
)

$AdminObjectIds
```

Every value must be a nonempty GUID.

## 8.2 Select or create the Prod workspace

```powershell
terraform -chdir=terraform workspace select prod
if ($LASTEXITCODE -ne 0) {
  terraform -chdir=terraform workspace new prod
}

terraform -chdir=terraform workspace show
```

Expected: `prod`.

## 8.3 Validate and create the first-stage Prod foundation

Pass runtime-specific values without editing tracked tfvars:

Important: use this complete variable set for the first local Prod deployment.
After public access is disabled, run later Prod plans from the private runner
or another approved host in the VNet because Terraform must read Key Vault
secret resources. The current GitHub Terraform workflow uses a GitHub-hosted
runner and supplies
`APPLICATION_BASE_URL`, but it does not map `admin_member_object_ids`,
`notification_sender_user_id`, or `contact_notification_recipient` into the
Terraform process. Running its Prod apply with the current workflow would plan
those values back to their tfvars defaults. Do not run the Prod Terraform
workflow until a reviewed workflow change preserves all four values.

```powershell
$AdminIdsJson = ConvertTo-Json -InputObject @($AdminObjectIds) -Compress

terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate

terraform -chdir=terraform plan `
  -var-file="environments/prod/terraform.tfvars" `
  -var="application_base_url=$ProdBaseUrl" `
  -var="admin_member_object_ids=$AdminIdsJson" `
  -var="notification_sender_user_id=$NotificationSender" `
  -var="contact_notification_recipient=$ContactRecipient" `
  -target=module.resource_group `
  -target=module.storage `
  -target=module.entra `
  -target=module.key_vault `
  -out="prod-foundation.tfplan"

terraform -chdir=terraform apply "prod-foundation.tfplan"
```

Grant the bootstrap engineer temporary Prod Key Vault data-plane access:

```powershell
$ProdKeyVaultId = az keyvault show `
  --resource-group $ProdResourceGroup `
  --name $ProdKeyVaultName `
  --query id `
  -o tsv

az role assignment create `
  --assignee-object-id $SignedInObjectId `
  --assignee-principal-type User `
  --role "Key Vault Secrets Officer" `
  --scope $ProdKeyVaultId
```

Wait up to five minutes for RBAC propagation.

## 8.4 Create and review the complete Prod plan

```powershell
terraform -chdir=terraform plan `
  -var-file="environments/prod/terraform.tfvars" `
  -var="application_base_url=$ProdBaseUrl" `
  -var="admin_member_object_ids=$AdminIdsJson" `
  -var="notification_sender_user_id=$NotificationSender" `
  -var="contact_notification_recipient=$ContactRecipient" `
  -out="prod.tfplan"
```

Approval point: a second engineer must review:

- No unexpected destroys or replacements
- P1v3 App Service
- EP1 Function plan
- Cosmos DB Mongo API with continuous backup
- Front Door Premium and WAF
- VNet, private endpoints, and private DNS
- Key Vault and Storage public access lockdown
- App Service public access lockdown after Front Door dependencies
- Managed identities and RBAC
- Monitoring and resource locks
- Correct custom domain

## 8.5 Apply Prod

```powershell
terraform -chdir=terraform apply "prod.tfplan"
```

Expected:

```text
Apply complete! Resources: <n> added, 0 changed, 0 destroyed.
```

Front Door origin traffic will not work until its managed private endpoint is
approved. The custom domain will not be active until DNS validation completes.

If this first apply stops because Azure will not associate the unvalidated
custom domain with the Front Door route:

1. Do not destroy or remove state.
2. Run the output command below to obtain the validation token.
3. Create the TXT record from Section 10.1.
4. Wait for domain validation to become `Approved`.
5. Rerun the complete plan command from Section 8.4.
6. Review and apply the new plan.

Capture outputs:

```powershell
$ProdDeploymentClientId = terraform -chdir=terraform output -raw deployment_entra_client_id
$ProdAdminClientId = terraform -chdir=terraform output -raw admin_entra_client_id
$ProdKeyVault = terraform -chdir=terraform output -raw key_vault_name
$ProdStorage = terraform -chdir=terraform output -raw storage_account_name
$ProdCosmosEndpoint = terraform -chdir=terraform output -raw cosmos_endpoint
$DomainValidationToken = terraform -chdir=terraform output -raw front_door_custom_domain_validation_token

$FrontDoorHost = az afd endpoint show `
  --resource-group $ProdResourceGroup `
  --profile-name $FrontDoorProfile `
  --endpoint-name $FrontDoorEndpoint `
  --query hostName `
  -o tsv
```

## 8.6 Grant Prod OIDC identity backend access

```powershell
$ProdDeploymentSpObjectId = az ad sp show `
  --id $ProdDeploymentClientId `
  --query id `
  -o tsv

az role assignment create `
  --assignee-object-id $ProdDeploymentSpObjectId `
  --assignee-principal-type ServicePrincipal `
  --role "Storage Blob Data Contributor" `
  --scope $StateStorageId

az role assignment create `
  --assignee-object-id $ProdDeploymentSpObjectId `
  --assignee-principal-type ServicePrincipal `
  --role "Reader" `
  --scope $StateStorageId
```

Configure the Prod GitHub variables from Section 3 after RBAC propagation.

## 8.7 Validate Prod infrastructure

```powershell
az group show --name $ProdResourceGroup --query properties.provisioningState -o tsv

az webapp show `
  --resource-group $ProdResourceGroup `
  --name $ProdWebApp `
  --query "{State:state,HttpsOnly:httpsOnly,PublicAccess:publicNetworkAccess,Identity:identity.principalId}" `
  -o table

az functionapp show `
  --resource-group $ProdResourceGroup `
  --name $ProdFunctionApp `
  --query "{State:state,HttpsOnly:httpsOnly,PublicAccess:publicNetworkAccess,Identity:identity.principalId}" `
  -o table

az cosmosdb show `
  --resource-group $ProdResourceGroup `
  --name "sapp-prod-mongo" `
  --query "{PublicAccess:publicNetworkAccess,Backup:backupPolicy.type,Kind:kind}" `
  -o table

az keyvault show `
  --resource-group $ProdResourceGroup `
  --name $ProdKeyVault `
  --query "{PublicAccess:properties.publicNetworkAccess,PurgeProtection:properties.enablePurgeProtection,SoftDeleteDays:properties.softDeleteRetentionInDays}" `
  -o table

az storage account show `
  --resource-group $ProdResourceGroup `
  --name $ProdStorage `
  --query "{PublicAccess:publicNetworkAccess,SharedKeys:allowSharedKeyAccess,HttpsOnly:enableHttpsTrafficOnly,TLS:minimumTlsVersion}" `
  -o table
```

Expected:

- App Service public access: disabled
- Function public access: disabled
- Cosmos DB public access: disabled
- Key Vault public access: disabled
- Storage public access: disabled
- Storage shared keys: disabled
- HTTPS and TLS 1.2 enforced

Production continuation order:

1. Return to Section 4 and create/register the private deployment runner.
2. Complete Section 9 and approve Front Door Private Link.
3. Complete Section 10 and activate the custom domain.
4. Deploy the Prod application in Section 10.3.
5. Continue to Sections 11 and 12 for authentication and email validation.

After the private runner exists, use it for future Prod Terraform maintenance.
SSH to the runner, clone the repository, sign in with an approved engineer
identity, initialize the backend, and select `prod`:

```bash
git clone https://github.com/Shubha-KA/organic-ghee.git ~/organic-ghee
cd ~/organic-ghee

az login --tenant '<tenant-id>' --use-device-code
az account set --subscription '<subscription-id>'

terraform -chdir=terraform init -reconfigure \
  -backend-config="resource_group_name=tfstate-rg" \
  -backend-config="storage_account_name=<state-storage-account>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=terraform.tfstate"

terraform -chdir=terraform workspace select prod
```

The maintenance engineer requires `Storage Blob Data Contributor` on the state
account and temporary `Key Vault Secrets Officer` on the Prod Key Vault. The
bootstrap engineer already receives these roles during this guide. Remove the
Key Vault role after activation and grant it just-in-time for later maintenance.
Run the complete production plan commands in `pwsh` on this private host.

# 9. Front Door Private Link Approval

Azure Front Door Premium creates a managed private endpoint request against the
App Service origin. Microsoft requires the origin owner to approve this request
before traffic can flow.

Microsoft guidance:

- [Secure an Azure Front Door origin with Private Link](https://learn.microsoft.com/azure/frontdoor/private-link)
- [Connect Front Door Premium to App Service with Private Link](https://learn.microsoft.com/azure/frontdoor/standard-premium/how-to-enable-private-link-web-app)

## 9.1 Portal method

1. Open `App Services > sapp-prod-appsvc`.
2. Open `Networking`.
3. Open `Private endpoint connections`.
4. Locate the pending request whose message references Front Door private
   origin access.
5. Select the request.
6. Select `Approve`.
7. Enter an approval description.
8. Wait several minutes for Front Door propagation.

Expected transition:

```text
Pending -> Approved -> Connected
```

The App Service connection state is normally `Approved`; Front Door origin
health and successful traffic confirm the effective `Connected` state.

## 9.2 Azure CLI method

List App Service private endpoint connections:

```powershell
$Connections = az network private-endpoint-connection list `
  --resource-group $ProdResourceGroup `
  --name $ProdWebApp `
  --type "Microsoft.Web/sites" `
  -o json | ConvertFrom-Json

$Connections |
  Select-Object name,
    @{Name="Status";Expression={$_.privateLinkServiceConnectionState.status}},
    @{Name="Description";Expression={$_.privateLinkServiceConnectionState.description}},
    id |
  Format-Table -AutoSize
```

Identify the pending Front Door request, then approve it:

```powershell
$FrontDoorConnection = $Connections |
  Where-Object {
    $_.privateLinkServiceConnectionState.status -eq "Pending" -and
    $_.privateLinkServiceConnectionState.description -match "Front Door"
  } |
  Select-Object -First 1

if (-not $FrontDoorConnection) {
  throw "No pending Front Door private endpoint connection was found."
}

az network private-endpoint-connection approve `
  --id $FrontDoorConnection.id `
  --description "Approved for Organic Ghee Front Door Premium origin"
```

Verify:

```powershell
az network private-endpoint-connection show `
  --id $FrontDoorConnection.id `
  --query "privateLinkServiceConnectionState.status" `
  -o tsv

az afd origin show `
  --resource-group $ProdResourceGroup `
  --profile-name $FrontDoorProfile `
  --origin-group-name "app-origin-group" `
  --origin-name "app-service" `
  --query "{Enabled:enabledState,Provisioning:provisioningState,PrivateLink:sharedPrivateLinkResource.status}" `
  -o table
```

Expected:

- Private endpoint status: `Approved`
- Origin enabled: `Enabled`
- Provisioning: `Succeeded`
- Front Door health becomes healthy after propagation

# 10. Custom Domain Activation

## 10.1 Create the validation TXT record

At the DNS provider create:

```text
Type:  TXT
Name:  _dnsauth.www
Value: <value of $DomainValidationToken>
TTL:   300
```

For another subdomain, replace `www` consistently.

Verify public propagation:

```powershell
Resolve-DnsName -Name "_dnsauth.$ProdHostName" -Type TXT
```

Expected: the returned TXT value exactly matches `$DomainValidationToken`.

Check Front Door validation:

```powershell
az afd custom-domain show `
  --resource-group $ProdResourceGroup `
  --profile-name $FrontDoorProfile `
  --custom-domain-name "sapp-prod-domain" `
  --query "{Provisioning:provisioningState,Validation:domainValidationState,Certificate:tlsSettings.certificateType}" `
  -o table
```

Expected:

- Provisioning: `Succeeded`
- Validation: `Approved`
- Certificate: `ManagedCertificate`

## 10.2 Create the traffic CNAME

After validation, create:

```text
Type:  CNAME
Name:  www
Value: <value of $FrontDoorHost>
TTL:   300
```

Do not proxy the record through another CDN.

Verify:

```powershell
Resolve-DnsName -Name $ProdHostName -Type CNAME
```

Expected: canonical name equals `$FrontDoorHost`.

## 10.3 Validate certificate issuance and routing

Managed certificate issuance can take several minutes after validation and
route association.

Configure the Prod GitHub environment from Sections 3 and 8, confirm the
self-hosted runner is `Idle`, then deploy the application:

```powershell
gh workflow run "Deploy application" --ref main -f environment=prod
gh run list --workflow "Deploy application" --limit 5
```

Approve the protected `prod` GitHub environment when prompted. Expected:

- Build succeeds on the GitHub-hosted runner.
- Prod deployment runs on the runner labeled `prod-vnet`.
- Both private SCM DNS checks return `10.20.2.x` addresses.
- Web App and Function ZIP deployments succeed.

```powershell
curl.exe -I $ProdBaseUrl
curl.exe -sS "$ProdBaseUrl/health"
```

Expected:

- HTTPS certificate matches `$ProdHostName`.
- HTTP is redirected to HTTPS.
- `/health` eventually returns HTTP 200 after the application is deployed.
- Direct access to the App Service public hostname is blocked.

# 11. Microsoft Entra ID Activation

## 11.1 Add administrators

Terraform assigns the `Admin` app role to object IDs passed through
`admin_member_object_ids`. To add or remove administrators, create and review a
new Prod plan with the complete desired set:

After initial lockdown, run this Terraform change from `pwsh` on the private
runner using the maintenance access described in Section 8.7.

Administrators should normally be existing organizational users. If a tenant
administrator must create a cloud-only user, use a temporary password that
meets tenant policy and require immediate password change:

```powershell
$NewAdminUpn = "organic-ghee-admin@example.onmicrosoft.com"
$TemporaryPassword = Read-Host "Enter a tenant-compliant temporary password"

az ad user create `
  --display-name "Organic Ghee Administrator" `
  --user-principal-name $NewAdminUpn `
  --mail-nickname "organic-ghee-admin" `
  --password $TemporaryPassword `
  --force-change-password-next-sign-in true
```

Do not store the temporary password in the repository or command history.

```powershell
$AdminObjectIds = @(
  foreach ($Upn in $AdminUserUpns) {
    az ad user show --id $Upn --query id -o tsv
  }
)

$AdminIdsJson = ConvertTo-Json -InputObject @($AdminObjectIds) -Compress

terraform -chdir=terraform workspace select prod
terraform -chdir=terraform plan `
  -var-file="environments/prod/terraform.tfvars" `
  -var="application_base_url=$ProdBaseUrl" `
  -var="admin_member_object_ids=$AdminIdsJson" `
  -var="notification_sender_user_id=$NotificationSender" `
  -var="contact_notification_recipient=$ContactRecipient" `
  -out="prod-admins.tfplan"

terraform -chdir=terraform apply "prod-admins.tfplan"
```

## 11.2 Verify redirect and logout URIs

```powershell
az ad app show `
  --id $ProdAdminClientId `
  --query "{DisplayName:displayName,RedirectUris:web.redirectUris,LogoutUrl:web.logoutUrl}" `
  -o json
```

Expected:

```text
https://www.example.com/auth/entra/callback
https://www.example.com/
```

No production URI should use `azurewebsites.net`.

## 11.3 Verify the Admin app role and assignments

```powershell
$ProdAdminSpObjectId = az ad sp show --id $ProdAdminClientId --query id -o tsv

az ad app show `
  --id $ProdAdminClientId `
  --query "appRoles[].{DisplayName:displayName,Value:value,Enabled:isEnabled}" `
  -o table

az rest `
  --method GET `
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ProdAdminSpObjectId/appRoleAssignedTo" `
  --query "value[].{Principal:principalDisplayName,PrincipalId:principalId,AppRoleId:appRoleId}" `
  -o table
```

Expected:

- Role value: `Admin`
- Role enabled: `true`
- Every approved administrator appears in the assignment list

## 11.4 Validate login and logout

1. Open `$ProdBaseUrl/auth/admin/login` in a private browser.
2. Sign in with an assigned administrator.
3. Confirm redirect to `/dashboard`.
4. Confirm access to an `/admin/*` page.
5. Sign out through `/auth/admin/logout`.
6. Confirm the Entra logout flow returns to `$ProdBaseUrl/`.
7. Sign in with an unassigned tenant user.
8. Confirm the callback returns HTTP 403.

# 12. Email Activation

## 12.1 Configure addresses

`notification_sender_user_id` accepts the sender's Entra object ID or user
principal name. The sender mailbox must exist and be licensed to send mail.
`contact_notification_recipient` must be a valid mailbox.

The values were passed during Prod apply:

```text
notification_sender_user_id    = notifications@example.com
contact_notification_recipient = orders@example.com
```

To change them, rerun the reviewed Prod plan using the same variables from
Section 8.

## 12.2 Verify Function identity and Graph permission

```powershell
$FunctionPrincipalId = az functionapp identity show `
  --resource-group $ProdResourceGroup `
  --name $ProdFunctionApp `
  --query principalId `
  -o tsv

az rest `
  --method GET `
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$FunctionPrincipalId/appRoleAssignments" `
  --query "value[].{Resource:resourceDisplayName,AppRoleId:appRoleId}" `
  -o table
```

Expected: an assignment for Microsoft Graph. Terraform maps this assignment to
the Graph `Mail.Send` application role.

## 12.3 Verify Queue and Function configuration

```powershell
az storage queue show `
  --account-name $ProdStorage `
  --name "order-notifications" `
  --auth-mode login `
  -o table

az functionapp config appsettings list `
  --resource-group $ProdResourceGroup `
  --name $ProdFunctionApp `
  --query "[?name=='NOTIFICATION_SENDER_USER_ID' || name=='CONTACT_NOTIFICATION_RECIPIENT' || name=='ORDER_NOTIFICATIONS_QUEUE'].{Name:name,Value:value}" `
  -o table
```

Expected:

- Queue exists.
- Queue setting is `order-notifications`.
- Sender and recipient match approved mailboxes.

Run storage commands from the production runner or another host that can
resolve and reach the private Storage endpoint.

## 12.4 End-to-end order email test

1. Deploy the Prod application using Section 13's application workflow step.
2. Register a customer using a test mailbox.
3. Add a dish to the cart.
4. Place an order.
5. Confirm an Order document is created.
6. Confirm a message appears briefly in `order-notifications`.
7. Confirm the Function execution succeeds.
8. Confirm the test customer receives the order confirmation.

Inspect Function logs:

```powershell
az webapp log tail `
  --resource-group $ProdResourceGroup `
  --name $ProdFunctionApp
```

## 12.5 End-to-end contact email test

1. Submit the public contact form.
2. Confirm a `contact` notification reaches the queue.
3. Confirm the Function succeeds.
4. Confirm `$ContactRecipient` receives the message.

If Graph returns 403, verify:

- Function managed identity app-role assignment is `Mail.Send`.
- The sender mailbox exists and is licensed.
- Tenant application-access policies do not block the mailbox.
- RBAC and Graph consent have propagated.

# 13. Go-Live Checklist

## Infrastructure

- [ ] Backend storage is protected by versioning, soft delete, and lock.
- [ ] Dev apply completed without unexpected resources.
- [ ] Prod apply completed without unexpected replacement or destruction.
- [ ] App Service is P1v3.
- [ ] Function plan is EP1.
- [ ] Cosmos DB Mongo API is provisioned.
- [ ] Storage uses ZRS in Prod.
- [ ] Resource tags identify environment, owner, cost center, and Terraform.

## Security

- [ ] No publish profiles or Azure client secrets exist in GitHub.
- [ ] GitHub OIDC federation works for `dev` and `prod`.
- [ ] Prod GitHub environment requires reviewers.
- [ ] App Service and Function identities are enabled.
- [ ] Key Vault uses RBAC.
- [ ] Key Vault purge protection is enabled.
- [ ] Storage shared-key access is disabled in Prod.
- [ ] HTTPS and TLS 1.2 are enforced.
- [ ] FTP and basic deployment authentication are disabled.
- [ ] Key Vault and Storage have `CanNotDelete` locks.
- [ ] Admin role assignments contain only approved users or groups.

## Networking

- [ ] Front Door managed private endpoint request is approved.
- [ ] Front Door origin reports healthy.
- [ ] App Service public access is disabled.
- [ ] Function public access is disabled.
- [ ] Cosmos DB public access is disabled.
- [ ] Key Vault public access is disabled.
- [ ] Storage public access is disabled.
- [ ] All private endpoint connections are approved.
- [ ] Private DNS zones are linked to `sapp-prod-vnet`.
- [ ] Runner resolves App Service and Function SCM hostnames to private IPs.
- [ ] Runner NSG allows SSH only from an approved source.

## Monitoring

- [ ] Application Insights receives Web App telemetry.
- [ ] Application Insights receives Function telemetry.
- [ ] Log Analytics receives App Service diagnostics.
- [ ] Log Analytics receives Key Vault audit logs.
- [ ] Log Analytics receives Storage account, Blob, and Queue diagnostics.
- [ ] Log Analytics receives Cosmos DB diagnostics.
- [ ] Front Door and WAF health are reviewed.
- [ ] Test failures are visible to the operations team.

## Authentication

- [ ] Customer registration and login succeed.
- [ ] Customer passwords are stored as bcrypt hashes.
- [ ] Customer can view and cancel only their own orders.
- [ ] Assigned administrator can sign in through Entra ID.
- [ ] Unassigned administrator receives HTTP 403.
- [ ] Login callback uses the custom production domain.
- [ ] Logout returns to the custom production domain.

## Application and Notifications

- [ ] Prod application workflow completed on the private runner.
- [ ] `/health` returns HTTP 200 through Front Door.
- [ ] Product image upload and retrieval succeed.
- [ ] Order placement succeeds.
- [ ] Queue trigger processes order messages.
- [ ] Order confirmation email is received.
- [ ] Contact notification email is received.

## Backup and Disaster Recovery

- [ ] Cosmos DB reports Continuous backup.
- [ ] Key Vault soft-delete retention is 90 days.
- [ ] Key Vault purge protection is enabled.
- [ ] Application blob versioning and retention are enabled.
- [ ] Terraform state versioning and 30-day retention are enabled.
- [ ] A local encrypted state backup has been tested.
- [ ] Recovery owners, RPOs, and RTOs are accepted.
- [ ] A restore drill date is scheduled.

## Production deployment evidence

The application was deployed in Section 10.3. Confirm its approved workflow
evidence:

```powershell
gh run list --workflow "Deploy application" --limit 5
gh run view <successful-run-id>
```

Expected:

- Build succeeds on GitHub-hosted runner.
- Prod deployment runs on `sapp-prod-gh-runner-01`.
- Private SCM resolution checks succeed.
- Web App and Function ZIP deployments succeed.

# 14. Operations Guide

Run all Prod Terraform commands in this section from `pwsh` on the private
runner or another approved host with private Key Vault connectivity. Supply
the same complete variable set used during the initial Prod deployment.

## Monthly tasks

- Review Azure Cost Management actual versus budget.
- Review Front Door request volume, origin latency, 4xx/5xx rates, and health.
- Review WAF blocked requests, false positives, bot activity, and rule updates.
- Review App Service and Function availability and failure rates.
- Review Cosmos DB request units, throttling, storage, and backup status.
- Review Storage growth, queue poison/retry behavior, and failed notifications.
- Review Key Vault audit events and denied requests.
- Review Defender for Cloud recommendations.
- Review Terraform plan drift with a refresh-only plan:

```powershell
terraform -chdir=terraform workspace select prod
terraform -chdir=terraform plan `
  -refresh-only `
  -var-file="environments/prod/terraform.tfvars" `
  -var="application_base_url=$ProdBaseUrl" `
  -var="admin_member_object_ids=$AdminIdsJson" `
  -var="notification_sender_user_id=$NotificationSender" `
  -var="contact_notification_recipient=$ContactRecipient"
```

- Patch the runner OS:

```bash
sudo apt-get update
sudo apt-get upgrade -y
sudo systemctl status actions.runner.*
```

## Quarterly tasks

- Review Azure and Entra RBAC assignments for least privilege.
- Review GitHub repository and environment administrators.
- Review OIDC federated subjects and remove obsolete credentials.
- Rotate the Terraform-managed Entra admin client secret through a reviewed
  Terraform replacement window.
- Validate session-secret rotation procedure and user-session impact.
- Review npm dependencies and security advisories.
- Test restoration of a nonproduction blob version.
- Pull and verify Terraform state backup:

Create and review the secret-rotation plan during an approved outage window:

```powershell
terraform -chdir=terraform workspace select prod
terraform -chdir=terraform plan `
  -var-file="environments/prod/terraform.tfvars" `
  -var="application_base_url=$ProdBaseUrl" `
  -var="admin_member_object_ids=$AdminIdsJson" `
  -var="notification_sender_user_id=$NotificationSender" `
  -var="contact_notification_recipient=$ContactRecipient" `
  -replace="module.entra.azuread_application_password.admin" `
  -replace="random_password.session_secret" `
  -out="prod-secret-rotation.tfplan"

terraform -chdir=terraform apply "prod-secret-rotation.tfplan"
az webapp restart --resource-group $ProdResourceGroup --name $ProdWebApp
```

This invalidates existing customer and administrator sessions. Validate both
login flows immediately after the restart.

Pull and verify Terraform state backup:

```powershell
New-Item -ItemType Directory -Force ".terraform-backups" | Out-Null
terraform -chdir=terraform workspace select prod
terraform -chdir=terraform state pull |
  Set-Content ".terraform-backups/prod-$(Get-Date -Format yyyyMMdd-HHmmss).tfstate"
```

- Confirm the backup is encrypted at rest and excluded from source control.

## Yearly tasks

- Perform a full disaster-recovery exercise.
- Test Cosmos DB point-in-time restore into a new account.
- Test Key Vault recovery in an isolated exercise.
- Test restoration of Terraform state from a prior blob version.
- Rebuild the self-hosted runner from a clean VM.
- Review App Service, Function, Cosmos, Front Door, and Terraform provider
  versions.
- Review domain registration, registrar MFA, DNS ownership, and certificate
  renewal.
- Reassess RPO, RTO, regional resilience, capacity, and cost.
- Perform an external penetration test and remediate findings.

# 15. Disaster Recovery

Do not run destructive recovery commands during routine validation. Open an
incident, identify the recovery point, back up current state where possible,
and obtain change approval.

## Recovery targets

| Component | Target RPO | Target RTO | Protection |
| --- | --- | --- | --- |
| Terraform state | 15 minutes | 2 hours | Blob lease, versions, 30-day soft delete |
| Front Door configuration | Repository/current state | 2 hours | Terraform recreation |
| Cosmos DB | Up to 7 days PITR, selected timestamp | 4 hours | Continuous7Days backup |
| Application Blob Storage | Latest retained version | 4 hours | ZRS, versions, soft delete |
| Key Vault | Latest retained object | 2 hours | 90-day soft delete and purge protection |
| App Service | Last approved package | 1 hour | GitHub artifact/redeployment |
| Function App | Last approved package | 1 hour | GitHub artifact/redeployment |

Actual recovery time depends on Azure service recovery duration, DNS TTL, data
volume, and incident approval speed.

## 15.1 Terraform state recovery

Create a safety backup:

```powershell
New-Item -ItemType Directory -Force ".terraform-backups" | Out-Null
terraform -chdir=terraform workspace select prod
terraform -chdir=terraform state pull |
  Set-Content ".terraform-backups/prod-before-recovery-$(Get-Date -Format yyyyMMdd-HHmmss).tfstate"
```

List state blobs and versions:

```powershell
az storage blob list `
  --account-name $StateStorageAccount `
  --container-name $StateContainer `
  --include v `
  --auth-mode login `
  --query "[].{Name:name,VersionId:versionId,Current:isCurrentVersion,Modified:properties.lastModified}" `
  -o table
```

Identify the correct workspace state blob and version. Promote a previous
version by copying it over the base blob:

```powershell
$StateBlobName = "<exact-workspace-state-blob-name>"
$GoodVersionId = "<version-id>"
$SourceUri = "https://$StateStorageAccount.blob.core.windows.net/$StateContainer/$StateBlobName?versionId=$GoodVersionId"

az storage blob copy start `
  --account-name $StateStorageAccount `
  --destination-container $StateContainer `
  --destination-blob $StateBlobName `
  --source-uri $SourceUri `
  --auth-mode login
```

Reinitialize and verify:

```powershell
terraform -chdir=terraform init -reconfigure `
  -backend-config="resource_group_name=$StateResourceGroup" `
  -backend-config="storage_account_name=$StateStorageAccount" `
  -backend-config="container_name=$StateContainer" `
  -backend-config="key=terraform.tfstate"

terraform -chdir=terraform workspace select prod
terraform -chdir=terraform state list
```

Never use `terraform force-unlock` unless no Terraform process is active and
the lock ID has been independently verified.

## 15.2 Front Door recovery

1. Confirm DNS still resolves to the Front Door endpoint.
2. Check profile, endpoint, origin, route, WAF, domain, and private-link state.
3. Reapprove a replacement managed private endpoint if Front Door recreated it.
4. Run a reviewed Terraform plan.
5. Apply only the approved Front Door changes.

```powershell
az afd profile show -g $ProdResourceGroup -n $FrontDoorProfile -o table
az afd endpoint show -g $ProdResourceGroup --profile-name $FrontDoorProfile -n $FrontDoorEndpoint -o table

terraform -chdir=terraform workspace select prod
terraform -chdir=terraform plan `
  -var-file="environments/prod/terraform.tfvars" `
  -var="application_base_url=$ProdBaseUrl" `
  -var="admin_member_object_ids=$AdminIdsJson" `
  -var="notification_sender_user_id=$NotificationSender" `
  -var="contact_notification_recipient=$ContactRecipient"
```

After replacement, repeat Sections 9 and 10.

## 15.3 Cosmos DB recovery

Continuous backup restores to a new Cosmos DB account. It does not overwrite
the source account.

1. Identify the last known good UTC timestamp.
2. In Azure Portal, open the Cosmos DB account.
3. Select `Point in Time Restore`.
4. Choose the timestamp and a new globally unique target account name.
5. Restore the required Mongo database.
6. Validate document counts and representative records.
7. Use a reviewed Terraform and Key Vault change to point the application at
   the restored account.
8. Restart the App Service and validate `/health`, login, catalog, and orders.

List restorable accounts with Azure CLI:

```powershell
az cosmosdb restorable-database-account list `
  --location $Location `
  --account-name "sapp-prod-mongo" `
  -o table
```

Restore the account to a new globally unique name:

```powershell
$RestoreTimestampUtc = "<YYYY-MM-DDTHH:MM:SS+0000>"
$RestoredCosmosAccount = "sapp-prod-mongo-restore-$(Get-Date -Format yyyyMMdd)"

az cosmosdb restore `
  --resource-group $ProdResourceGroup `
  --target-database-account-name $RestoredCosmosAccount `
  --account-name "sapp-prod-mongo" `
  --restore-timestamp $RestoreTimestampUtc `
  --location $Location `
  --public-network-access DISABLED
```

Expected: a new Cosmos DB account reaches provisioning state `Succeeded`.

The current Terraform module owns the original account name and cannot
automatically adopt a point-in-time restore account with a different name.
Production cutover therefore requires an approved incident change that:

1. Adds private endpoint and private DNS connectivity for the restored account.
2. Updates the Key Vault `database-connection-string` secret to the restored
   account.
3. Restarts and validates App Service.
4. Reconciles the restored account into Terraform before the next routine
   apply.

Do not enable public Cosmos DB access as a shortcut. Record the source account,
restore timestamp, target account, private endpoint, secret version, and
validation evidence in the incident.

## 15.4 Storage recovery

For a deleted or overwritten product image:

1. Open the Storage Account.
2. Open `Containers > appblob`.
3. Enable `Show deleted blobs`.
4. Select the blob.
5. Select `Undelete`.
6. Open `Versions`.
7. Select the correct version and choose `Make current version`.
8. Validate the product image URL through Front Door.

CLI inventory:

```powershell
az storage blob list `
  --account-name $ProdStorage `
  --container-name appblob `
  --include dv `
  --auth-mode login `
  --query "[].{Name:name,Deleted:deleted,VersionId:versionId,Current:isCurrentVersion}" `
  -o table
```

For account loss beyond soft-delete coverage, recreate infrastructure with
Terraform and restore data from the approved external backup copy. ZRS protects
against zone failure but is not a substitute for independent backup.

## 15.5 Key Vault recovery

List deleted vaults:

```powershell
az keyvault list-deleted `
  --subscription $SubscriptionId `
  --resource-type vault `
  -o table
```

Recover the production vault:

```powershell
az keyvault recover `
  --subscription $SubscriptionId `
  --name $ProdKeyVault
```

Verify:

```powershell
az keyvault show `
  --subscription $SubscriptionId `
  --name $ProdKeyVault `
  --query "{Name:name,Provisioning:properties.provisioningState,PurgeProtection:properties.enablePurgeProtection}" `
  -o table
```

For an individual secret:

```powershell
az keyvault secret list-deleted --vault-name $ProdKeyVault -o table
az keyvault secret recover --vault-name $ProdKeyVault --name "<secret-name>"
```

Do not use `az keyvault purge`. Purge protection intentionally prevents
permanent deletion during the retention period.

## 15.6 App Service recovery

1. Check Front Door origin health and App Service state.
2. Confirm private SCM DNS from the runner.
3. Redeploy the last approved application commit through the manual Prod
   workflow.
4. Validate `/health`, customer login, admin login, catalog, and order flow.

```powershell
gh workflow run "Deploy application" --ref "<known-good-commit-or-branch>" -f environment=prod
gh run list --workflow "Deploy application" --limit 5
```

If the infrastructure resource is missing, run a reviewed Terraform plan
before application redeployment.

## 15.7 Function recovery

1. Confirm Function App state and managed identity.
2. Confirm private DNS and SCM resolution from the runner.
3. Confirm Queue, Key Vault, Storage, and Graph role assignments.
4. Redeploy the known-good package through the Prod application workflow.
5. Send one test order message.
6. Verify Function execution and email delivery.

```powershell
az functionapp show `
  --resource-group $ProdResourceGroup `
  --name $ProdFunctionApp `
  --query "{State:state,Identity:identity.principalId,PublicAccess:publicNetworkAccess}" `
  -o table
```

## 15.8 Recovery completion criteria

- Front Door serves the custom domain with a valid certificate.
- WAF is enabled in Prevention mode.
- App Service and Function public access remain disabled.
- `/health` returns HTTP 200.
- Customer and administrator authentication work.
- Catalog reads and product image access work.
- Order creation and ownership checks work.
- Queue-triggered order and contact emails work.
- Monitoring receives fresh telemetry.
- A refresh-only Terraform plan shows no unexplained drift.
- Incident evidence records recovery point, recovery time, validation, and
  follow-up actions.

# Official References

- [Azure resource provider registration](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types)
- [Azure Front Door Private Link](https://learn.microsoft.com/azure/frontdoor/private-link)
- [Front Door to App Service with Private Link](https://learn.microsoft.com/azure/frontdoor/standard-premium/how-to-enable-private-link-web-app)
- [Azure Front Door custom domains](https://learn.microsoft.com/azure/frontdoor/standard-premium/how-to-add-custom-domain)
- [GitHub self-hosted runners](https://docs.github.com/actions/how-tos/manage-runners/self-hosted-runners/add-runners)
- [Azure App Service ZIP deployment](https://learn.microsoft.com/azure/app-service/deploy-zip)
- [Azure CLI role assignments](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-cli)
- [Key Vault recovery](https://learn.microsoft.com/azure/key-vault/general/key-vault-recovery)
- [Blob soft-delete recovery](https://learn.microsoft.com/azure/storage/blobs/soft-delete-blob-manage)
- [Blob versioning](https://learn.microsoft.com/azure/storage/blobs/versioning-enable)
