# Disaster Recovery Guide

Purpose
- Define recovery plans, RPO/RTO targets and operational steps to recover platform and application resources.

1. Recovery targets (recommended)
- RPO: 4 hours for application data (MongoDB backups), 24 hours for state and configuration
- RTO: 1 hour for platform-level resources (App Service redeploy), 4 hours for full application recovery (data restore included)

2. What to backup
- Application data: MongoDB (use Atlas or VM snapshots or managed CosmosDB backups if applicable)
- Storage Account (blobs and state backup copies)
- Key Vault (secrets should be replicated by manually exporting or using soft-delete/versioning)
- Terraform state (regular export to secondary storage/region)

3. Backup mechanisms
- MongoDB: use scheduled logical backups or managed backups (if using CosmosDB, configure continuous backup with point-in-time restore)
- Storage Account: enable blob versioning and soft delete; configure lifecycle policy to copy state blobs to another storage account in a secondary region nightly
- Key Vault: enable soft-delete and purge-protection; store critical secrets in a secondary Key Vault or securely export secrets (encrypted) for DR procedures
- Terraform state: schedule `az storage blob copy start` from primary state blob to a DR storage account daily and keep versioned copies

4. Disaster recovery playbook (short)
- Scenario A: App Service failure (in-region)
  1. Check App Service diagnostics and logs.
  2. If corrupt deployment, rollback to previous working deployment (use deployment history or re-deploy from artifact store).
  3. If app plan or underlying infra failed, re-run `terraform apply` in the appropriate workspace (after validating state and drift).

- Scenario B: Storage Account compromised or deleted
  1. Attempt to recover using Blob soft-delete or blob version history.
  2. If not available, restore state from DR storage account backup and reinitialize backend using `terraform init -reconfigure` with the DR backend, then `terraform apply` to bring resources up.

- Scenario C: Key Vault deleted
  1. If soft-delete enabled, recover Key Vault via portal or CLI: `az keyvault purge --location <location> --name <kv>` (note purge is permanent)
  2. If not recoverable, restore secrets from encrypted backup and re-seed secrets in a new Key Vault.

5. Runbook snippets
```bash
# Copy state blob to DR storage account
az storage blob copy start --destination-blob tfstate --destination-container tfstate --account-name drstateacct --source-uri "https://primary.blob.core.windows.net/tfstate/terraform.tfstate"
```

6. Testing DR
- Run an annual DR drill: simulate region failure and restore infrastructure in secondary region using DR state.
- Validate application, secrets access, and data store availability.
