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

variable "alert_email_from" {
  description = "Gmail address to send alerts from"
  type        = string
}

variable "alert_email_password" {
  description = "Gmail app password (not your regular password — create at myaccount.google.com/apppasswords)"
  type        = string
  sensitive   = true
}
