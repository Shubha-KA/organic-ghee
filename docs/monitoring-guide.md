# Monitoring Guide

Goal
- Provide steps to configure telemetry, logs and alerts for the application and platform.

1. Components
- Application Insights (request, dependency, exception telemetry)
- Log Analytics Workspace (central logs)
- Diagnostic Settings for Key Vault, Storage, App Service
- Alerts and Dashboards

2. Create Log Analytics and Application Insights

Portal steps
- Portal navigation: Log Analytics workspaces -> + Create -> fill name `la-<project>-prod` -> Create.
- Portal navigation: Application Insights -> + Create -> Resource Group -> Name `ai-<project>-prod` -> Choose Workspace-based and link to the Log Analytics created above -> Create.

CLI snippets
```bash
az monitor log-analytics workspace create -g <rg> -n la-<project>-prod -l eastus
az monitor app-insights component create -g <rg> -a ai-<project>-prod -l eastus --application-type web --workspace <workspace_resource_id>
```

3. Diagnostic settings
- For each resource (Key Vault, Storage Account, App Service) configure Diagnostic Settings to send logs to the Log Analytics workspace and optionally to Storage/ Event Hub.

Portal steps (App Service example)
- App Service -> Diagnostic settings -> + Add diagnostic setting -> send 'AppServiceHTTPLogs', 'AppServiceConsoleLogs', 'AppServicePlatformLogs' to your Log Analytics workspace.

4. Alerts and recommended rules
- Critical alerts:
  - App failures or high rate of 5xx errors (Application Insights) — Action: Pager/Slack/Teams notification
  - Key Vault access denied spikes (Log Analytics) — Action: Security alert
  - Storage account throttling or high success/error ratios — Action: Ops alert
  - Deployment failure or terraform apply errors (CI) — Action: CI notifications

Example Alert rules
```text
- AI Server Response Time > 1.5s (5m)
- Failed Requests (5xx) > 1% of requests (5m)
- Exceptions rate increase by > 50% (5m)
- CPU > 80% for 5 minutes on AppService Plan
```

5. Dashboards
- Create an Azure Dashboard with tiles for:
  - Application requests, failures, avg duration
  - Key Vault operation counts and errors
  - Storage capacity and access operations
  - Terraform last deployment time and status (via CI integration)

6. Log queries examples
```kusto
# Failed requests
requests | where success == false | summarize count() by resultCode, bin(timestamp, 5m)

# Key Vault operation failures
AzureDiagnostics | where ResourceType == "VAULTS" and log_s == "AuditEvent" and Activity == "SecretGet" and status_s != "Success"
```

7. Integration with PagerDuty/Teams/Slack
- Use Action Groups in Azure Monitor to forward alerts to external systems.
