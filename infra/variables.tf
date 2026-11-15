variable "region" {
  description = "Region de AWS."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nombre del proyecto; se usa en tags y nombres."
  type        = string
  default     = "devsecops-demo"
}

variable "vms" {
  description = "Mapa de VPS por rol y tipo de instancia (verifica los tipos permitidos por tu plan gratuito)."
  type        = map(string)
  default = {
    gateway = "t3.micro"
    app     = "t3.micro"
    ops     = "t3.small"
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "github_repo" {
  description = "Repositorio GitHub 'owner/nombre' autorizado a desplegar via OIDC. Vacio = no crear rol."
  type        = string
  default     = ""
}

variable "create_github_oidc_provider" {
  description = "Poner false si tu cuenta ya tiene el proveedor OIDC de GitHub (solo puede existir uno)."
  type        = bool
  default     = true
}
