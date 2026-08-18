locals {
  cae_name    = "cae-${var.platform_name_prefix}"
  acr_name    = "acr${var.platform_name_prefix}"
  psql_name   = "psql-${var.platform_name_prefix}"
  vnet_name   = "vnet-${var.platform_name_prefix}"
  app_db_name = replace(var.app_name, "-", "_")

  kv_name      = "kv-${substr(replace(var.app_name, "-", ""), 0, 14)}-${substr(md5(var.app_name), 0, 6)}"
  storage_name = "st${substr(replace(var.app_name, "-", ""), 0, 16)}${substr(md5(var.app_name), 0, 6)}"

  # Container Apps secret names and Key Vault secret names only allow lowercase alphanumerics and
  # dashes, so the UPPER_SNAKE_CASE names declared at onboarding get a deterministic, one-way
  # transform here. The env var the app reads keeps the original declared name unchanged.
  kv_secret_name = { for n in var.secret_names : n => lower(replace(n, "_", "-")) }

  base_env = [
    { name = "PORT", value = tostring(var.container_port), secret_name = null },
    { name = "AZURE_CLIENT_ID", value = data.azurerm_user_assigned_identity.app.client_id, secret_name = null },
  ]

  db_env = var.enable_database ? [
    { name = "POSTGRES_HOST", value = data.azurerm_postgresql_flexible_server.platform[0].fqdn, secret_name = null },
    { name = "POSTGRES_PORT", value = "5432", secret_name = null },
    { name = "POSTGRES_USER", value = data.azurerm_user_assigned_identity.app.name, secret_name = null },
    { name = "POSTGRES_DB", value = local.app_db_name, secret_name = null },
    { name = "POSTGRES_SSL", value = "require", secret_name = null },
  ] : []

  secret_env = var.enable_secrets ? [
    for n in var.secret_names : { name = n, value = null, secret_name = local.kv_secret_name[n] }
  ] : []

  storage_env = var.enable_storage ? [
    { name = "STORAGE_ACCOUNT_NAME", value = azurerm_storage_account.app[0].name, secret_name = null },
    { name = "STORAGE_CONTAINER_NAME", value = "data", secret_name = null },
  ] : []

  container_env = concat(local.base_env, local.db_env, local.secret_env, local.storage_env)

  action_group_id = var.alert_email != "" ? azurerm_monitor_action_group.app_alerts[0].id : data.azurerm_monitor_action_group.platform_alerts.id
}

data "azurerm_resource_group" "app" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

data "azurerm_container_app_environment" "platform" {
  name                = local.cae_name
  resource_group_name = var.platform_resource_group_name
}

data "azurerm_postgresql_flexible_server" "platform" {
  count               = var.enable_database ? 1 : 0
  name                = local.psql_name
  resource_group_name = var.platform_resource_group_name
}

data "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.app_name}"
  resource_group_name = var.resource_group_name
}

data "azurerm_user_assigned_identity" "deploy" {
  count               = var.enable_secrets ? 1 : 0
  name                = "id-${var.app_name}-ci"
  resource_group_name = var.resource_group_name
}

data "azurerm_monitor_action_group" "platform_alerts" {
  name                = "ag-${var.platform_name_prefix}-alerts"
  resource_group_name = var.platform_resource_group_name
}

data "azurerm_subnet" "pe" {
  count                = var.enable_secrets || var.enable_storage ? 1 : 0
  name                 = "snet-pe"
  virtual_network_name = local.vnet_name
  resource_group_name  = var.platform_resource_group_name
}

data "azurerm_private_dns_zone" "kv" {
  count               = var.enable_secrets ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.platform_resource_group_name
}

data "azurerm_private_dns_zone" "blob" {
  count               = var.enable_storage ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.platform_resource_group_name
}

resource "azurerm_monitor_action_group" "app_alerts" {
  count               = var.alert_email != "" ? 1 : 0
  name                = "ag-${var.app_name}-alerts"
  resource_group_name = var.resource_group_name
  short_name          = substr("ag-${var.app_name}", 0, 12)
  tags                = var.tags

  email_receiver {
    name          = "app-owner"
    email_address = var.alert_email
  }
}

resource "azurerm_key_vault" "app" {
  count                      = var.enable_secrets ? 1 : 0
  name                       = local.kv_name
  resource_group_name        = var.resource_group_name
  location                   = data.azurerm_resource_group.app.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  # Secret VALUES are a data-plane operation: both Terraform (a GitHub-hosted runner) and the
  # Sync secrets workflow need to reach that data plane over the public internet, so this cannot
  # be network-restricted the way the database and storage are. RBAC is the real boundary here:
  # every operation still requires an Azure AD token and an explicit role scoped to this one
  # vault, so network reachability alone grants nothing. The private endpoint below still gives
  # the running container a private path when it resolves its own secret references.
  public_network_access_enabled = true
  tags                          = var.tags
}

resource "azurerm_private_endpoint" "kv" {
  count               = var.enable_secrets ? 1 : 0
  name                = "pe-${var.app_name}-kv"
  location            = data.azurerm_resource_group.app.location
  resource_group_name = var.resource_group_name
  subnet_id           = data.azurerm_subnet.pe[0].id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.app_name}-kv"
    private_connection_resource_id = azurerm_key_vault.app[0].id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.kv[0].id]
  }
}

resource "azurerm_role_assignment" "runtime_kv_secrets_user" {
  count                            = var.enable_secrets ? 1 : 0
  scope                            = azurerm_key_vault.app[0].id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = data.azurerm_user_assigned_identity.app.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "deploy_kv_secrets_officer" {
  count                            = var.enable_secrets ? 1 : 0
  scope                            = azurerm_key_vault.app[0].id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = data.azurerm_user_assigned_identity.deploy[0].principal_id
  skip_service_principal_aad_check = true
}

# Ensures each declared secret exists (holding a harmless placeholder) so the container app
# below always has something to resolve at create time. This is deliberately NOT a Terraform-
# tracked resource: az keyvault secret set is a data-plane upsert, so Sync secrets writing the
# real value first (or racing this) is never a conflict -- there's no resource identity here for
# Azure to report as "already exists", the class of error a tracked azurerm_key_vault_secret hit
# in practice when its create raced the RBAC grant above. Pruning removed names is the Sync
# secrets workflow's job now, not Terraform's for_each diff.
resource "terraform_data" "ensure_secret_placeholder" {
  for_each = var.enable_secrets ? local.kv_secret_name : {}

  triggers_replace = [each.value]

  depends_on = [
    azurerm_role_assignment.deploy_kv_secrets_officer,
    azurerm_role_assignment.runtime_kv_secrets_user,
    azurerm_private_endpoint.kv,
  ]

  provisioner "local-exec" {
    # local-exec runs via /bin/sh (dash on the Actions runner), not bash -- no pipefail here,
    # and none needed: this is a plain check-then-set with no pipe stage to lose an exit code on.
    command = <<-EOT
      set -eu
      az keyvault secret show --vault-name ${azurerm_key_vault.app[0].name} --name ${each.value} >/dev/null 2>&1 || \
        az keyvault secret set --vault-name ${azurerm_key_vault.app[0].name} --name ${each.value} --value REPLACE_ME --output none
    EOT
  }
}

resource "azurerm_storage_account" "app" {
  count                         = var.enable_storage ? 1 : 0
  name                          = local.storage_name
  resource_group_name           = var.resource_group_name
  location                      = data.azurerm_resource_group.app.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  public_network_access_enabled = false
  tags                          = var.tags
}

resource "azurerm_storage_container" "app" {
  count                 = var.enable_storage ? 1 : 0
  name                  = "data"
  storage_account_id    = azurerm_storage_account.app[0].id
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "blob" {
  count               = var.enable_storage ? 1 : 0
  name                = "pe-${var.app_name}-blob"
  location            = data.azurerm_resource_group.app.location
  resource_group_name = var.resource_group_name
  subnet_id           = data.azurerm_subnet.pe[0].id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.app_name}-blob"
    private_connection_resource_id = azurerm_storage_account.app[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.blob[0].id]
  }
}

resource "azurerm_role_assignment" "runtime_storage" {
  count                            = var.enable_storage ? 1 : 0
  scope                            = azurerm_storage_account.app[0].id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = data.azurerm_user_assigned_identity.app.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_container_app" "app" {
  name                         = var.app_name
  container_app_environment_id = data.azurerm_container_app_environment.platform.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.app.id]
  }

  registry {
    server   = "${local.acr_name}.azurecr.io"
    identity = data.azurerm_user_assigned_identity.app.id
  }

  dynamic "secret" {
    for_each = var.enable_secrets ? var.secret_names : []
    content {
      name                = local.kv_secret_name[secret.value]
      identity            = data.azurerm_user_assigned_identity.app.id
      key_vault_secret_id = "${azurerm_key_vault.app[0].vault_uri}secrets/${local.kv_secret_name[secret.value]}"
    }
  }

  ingress {
    external_enabled = true
    target_port      = var.container_port

    client_certificate_mode = "ignore"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 2

    container {
      name   = var.app_name
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.25
      memory = "0.5Gi"

      liveness_probe {
        transport               = "HTTP"
        port                    = var.container_port
        path                    = var.healthcheck_path
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = var.container_port
        path                    = var.healthcheck_path
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 6
      }

      dynamic "env" {
        for_each = local.container_env
        content {
          name        = env.value.name
          value       = env.value.secret_name == null ? env.value.value : null
          secret_name = env.value.secret_name
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [terraform_data.ensure_secret_placeholder]
}

resource "azurerm_monitor_metric_alert" "cpu" {
  name                = "alert-${var.app_name}-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_container_app.app.id]
  description         = "${var.app_name} container app CPU above 80% for 15 minutes."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = local.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "memory" {
  name                = "alert-${var.app_name}-memory"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_container_app.app.id]
  description         = "${var.app_name} container app memory above 80% for 15 minutes."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = local.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "restarts" {
  name                = "alert-${var.app_name}-restarts"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_container_app.app.id]
  description         = "${var.app_name} container app restarted at least once in 15 minutes (crash-loop signal)."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "RestartCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = local.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "down" {
  name                = "alert-${var.app_name}-down"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_container_app.app.id]
  description         = "${var.app_name} container app has zero healthy replicas."
  severity            = 0
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "Replicas"
    aggregation      = "Minimum"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = local.action_group_id
  }
}

output "container_app_fqdn" {
  description = "Public FQDN of the app's Container App."
  value       = azurerm_container_app.app.ingress[0].fqdn
}

output "app_database_name" {
  description = "Name of the app's database on the shared Postgres server, provisioned at landing-zone vend time (null if the database addon is disabled)."
  value       = var.enable_database ? local.app_db_name : null
}

output "key_vault_name" {
  description = "Name of this app's dedicated Key Vault (null if the secrets addon is disabled)."
  value       = var.enable_secrets ? local.kv_name : null
}

output "storage_account_name" {
  description = "Name of this app's dedicated Storage Account (null if the storage addon is disabled)."
  value       = var.enable_storage ? local.storage_name : null
}
