app_name                     = "athg-test"
resource_group_name          = "rg-ramboll-athg-test"
platform_resource_group_name = "rg-ramboll-poc"
platform_name_prefix         = "rambollpoc"
container_port               = 3000
healthcheck_path             = "/health"

enable_database  = false
alert_email      = ""

enable_secrets = false
secret_names   = []
enable_storage = false

tags = {
  environment   = "poc"
  owner         = "athg-syncable"
  team          = "group:default/software-engineering"
  "cost-center" = "software-engineering"
  project       = "ramboll-poc"
  "managed-by"  = "terraform"
}
