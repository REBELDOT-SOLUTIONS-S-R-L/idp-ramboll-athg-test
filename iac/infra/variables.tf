variable "subscription_id" {
  type        = string
  description = "Azure subscription id. CI passes this via ARM_SUBSCRIPTION_ID."
}

variable "app_name" {
  type        = string
  description = "Application name. Drives the container app, database, and managed identity names."

  validation {
    condition     = length(var.app_name) <= 21
    error_message = "app_name must be 21 characters or fewer so derived resource names stay within Azure limits."
  }
}

variable "resource_group_name" {
  type        = string
  description = "The app's own resource group (rg-ramboll-<app>), provisioned by the vending bootstrap. App resources land here."
}

variable "platform_resource_group_name" {
  type        = string
  description = "Shared platform resource group that holds the Container Apps environment, registry, and PostgreSQL server."
  default     = "rg-ramboll-poc"
}

variable "platform_name_prefix" {
  type        = string
  description = "Naming prefix used to look up the shared Container Apps environment, registry, and PostgreSQL server."
  default     = "rambollpoc"
}

variable "container_port" {
  type        = number
  description = "Port the container listens on. Also the ingress target port."
  default     = 8080
}

variable "healthcheck_path" {
  type        = string
  description = "HTTP path used by Container Apps liveness and readiness probes."
  default     = "/healthz"

  validation {
    condition = (
      can(regex("^/[A-Za-z0-9._~!$&()*+,;=:@%/-]+$", var.healthcheck_path)) &&
      !contains(["/", "/api/status"], var.healthcheck_path)
    )
    error_message = "healthcheck_path must be a safe non-root HTTP path and cannot be /api/status."
  }
}

variable "enable_database" {
  type        = bool
  description = "Provision a dedicated database on the shared Postgres server and inject POSTGRES_* env into the container."
  default     = false
}

variable "alert_email" {
  type        = string
  description = "Where this app's CPU/memory/restart/downtime alerts go. Empty uses the shared platform action group; a value provisions a dedicated action group for this app."
  default     = ""
}

variable "enable_secrets" {
  type        = bool
  description = "Provision a dedicated, private Key Vault for this app's own secrets. Values are set by the app owner after onboarding, never through Terraform."
  default     = false
}

variable "secret_names" {
  type        = list(string)
  description = "Names of secrets this app needs, e.g. [\"STRIPE_KEY\"]. Reserved in Key Vault and wired into the container as env vars; real values are set separately."
  default     = []

  validation {
    condition     = alltrue([for n in var.secret_names : can(regex("^[A-Z][A-Z0-9_]{0,62}$", n))])
    error_message = "secret_names must be UPPER_SNAKE_CASE, e.g. STRIPE_KEY."
  }
}

variable "enable_storage" {
  type        = bool
  description = "Provision a dedicated, private Storage Account and blob container for this app, accessed with its managed identity."
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
