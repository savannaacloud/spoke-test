variable "ssh_public_key" {
  description = "Public key injected into the keypair for SSH access."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Public DNS zone to create. Use a domain you own (or a placeholder like spoke-test.savannaa.com)."
  type        = string
  default     = "spoke-test.savannaa.com"
}

variable "db_admin_password" {
  description = "Admin password for the managed databases."
  type        = string
  default     = "ChangeMe-Spoke-Test-2026"
  sensitive   = true
}

variable "cache_password" {
  description = "AUTH password for Redis."
  type        = string
  default     = "ChangeMe-Cache-2026"
  sensitive   = true
}

variable "tier_workload_count" {
  description = "Number of workload instances per app tier (web, app, worker). Bumps the resource count linearly."
  type        = number
  default     = 3
}

variable "enable_kubernetes" {
  description = "Provision a Kubernetes cluster (~10 min, eats 3× m1.medium). Defaults OFF — flip to true for full coverage."
  type        = bool
  default     = false
}

variable "external_network_id" {
  description = "UUID of the external network for Kubernetes cluster floating IPs. Required only when enable_kubernetes = true."
  type        = string
  default     = ""
}
