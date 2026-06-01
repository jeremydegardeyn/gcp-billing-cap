variable "project_id" {
  description = "GCP project ID to protect"
  type        = string
}

variable "billing_account_id" {
  description = "GCP billing account ID (Billing > Account overview, format: XXXXXX-XXXXXX-XXXXXX)"
  type        = string
}

variable "region" {
  description = "Region for the Cloud Function"
  type        = string
  default     = "us-central1"
}

variable "monthly_budget_usd" {
  description = "Monthly spend cap in USD"
  type        = number
}

variable "threshold_fraction" {
  description = "Fraction of budget at which billing is disabled (1.0 = 100%)"
  type        = number
  default     = 1.0
}

variable "alert_email_to" {
  description = "Email address to notify when billing is disabled"
  type        = string
}

variable "smtp_host" {
  description = "SMTP host"
  type        = string
  default     = "smtp.gmail.com"
}

variable "smtp_port" {
  description = "SMTP port (STARTTLS)"
  type        = number
  default     = 587
}

variable "smtp_user" {
  description = "SMTP username"
  type        = string
}

variable "smtp_pass" {
  description = "SMTP password / app password"
  type        = string
  sensitive   = true
}

variable "smtp_from_email" {
  description = "From address on alert emails"
  type        = string
}

variable "smtp_from_name" {
  description = "From display name on alert emails"
  type        = string
  default     = "DataDinosaur"
}
