# Production Readiness Review

Purpose
- Final checklist and scorecard to validate production readiness across Reliability, Security, Operations, and Cost.

Scoring model (simple)
- Each category scored out of 10. Total possible: 60.

Categories
1. Security (10)
- Entra configuration follows least privilege.
- Key Vault soft-delete and purge-protection enabled.
- OIDC configured for CI; no long-lived secrets in GitHub.

2. Reliability & Availability (10)
- App Service Plan uses appropriate SKU; consider Zone redundancy or App Service Environment for high scale.
- Storage replication: LRS for cost, ZRS or GRS for higher resilience.

3. Observability (10)
- App Insights and Log Analytics configured and linked.
- Alert rules defined for critical failures and escalations.

4. CI/CD & Automation (10)
- Terraform workflows use remote state, formatting, validation, plan and apply steps with approvals for prod.
- OIDC for job identities and least privilege GitHub runners or hosted runners.

5. Backup & DR (10)
- State is versioned and backed up to secondary storage nightly.
- DB backups configured (MongoDB) with tested restores.

6. Cost & Governance (10)
- Tags are in place for chargeback.
- Azure Policy enforced for critical resource configuration.

Sample final checklist
- [ ] Remote state backend created and protected
- [ ] Terraform workspaces configured (dev/prod)
- [ ] OIDC configured for GitHub Actions
- [ ] App Service has Managed Identity and Key Vault access
- [ ] Diagnostic settings enabled for all resources
- [ ] App Insights instrumentation key present and verified
- [ ] Backup schedule defined and tested for DB and state
- [ ] Production branch protections and environment approvals in GitHub
- [ ] Security scans (Dependabot, SCA) configured
- [ ] DR plan documented and yearly DR drill scheduled

Overall architecture score and recommendation
- Evaluate each category and assign 0-10. Aim for 50+ to be considered production-ready.

Recommendations
- Short term (must do): enable Key Vault purge-protection, configure OIDC, protect backend with resource locks.
- Mid term: enable private endpoints for Key Vault and Storage, integrate Application Insights with Workbooks.
- Long term: consider multi-region active-passive with traffic manager and automated failover for critical services.
