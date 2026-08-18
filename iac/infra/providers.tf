provider "azurerm" {
  features {
    # Purging a deleted Key Vault is a subscription-wide action (see
    # role-ramboll-app-vending.json); the per-app deploy identity running this Terraform is
    # deliberately scoped to its own resource group and cannot do it. Leave the vault
    # soft-deleted on destroy; offboard-app.yml's own purge step (running as the privileged
    # vending identity) cleans it up afterward.
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
  subscription_id     = var.subscription_id
  use_oidc            = true
  storage_use_azuread = true
}
