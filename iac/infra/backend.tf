terraform {
  backend "azurerm" {
    resource_group_name  = "rg-ramboll-poc"
    storage_account_name = "strambollpoctfstate"
    container_name       = "tfstate-athg-test"
    key                  = "terraform.tfstate"
    use_oidc             = true
    use_azuread_auth     = true
  }
}
