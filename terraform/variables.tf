variable "project_id" {
  description = "GCP project ID to protect"
  type        = string
}

variable "billing_account_id" {
  description = "GCP billing account ID (find it in Billing > Account overview)"
  type        = string
}

variable "region" {
  description = "Region for the Cloud Function"
  type        = string
  default     = "us-central1"
}

variable "monthly_budget_usd" {
  description = "Monthly spend cap in USD — billing is killed at threshold_fraction of this"
  type        = number
}

variable "threshold_fraction" {
  description = "Fraction of budget at which billing is disabled (1.0 = 100%)"
  type        = number
  default     = 1.0
}
