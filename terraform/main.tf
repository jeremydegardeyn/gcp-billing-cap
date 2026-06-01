terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ── Pub/Sub topic that the budget alert will publish to ──────────────────────

resource "google_pubsub_topic" "billing_cap" {
  name = "billing-cap"
}

# ── Service account for the Cloud Function ───────────────────────────────────

resource "google_service_account" "billing_cap" {
  account_id   = "billing-cap-fn"
  display_name = "Billing Cap Cloud Function"
}

resource "google_project_iam_member" "billing_cap_manager" {
  project = var.project_id
  role    = "roles/billing.projectManager"
  member  = "serviceAccount:${google_service_account.billing_cap.email}"
}

resource "google_project_iam_member" "billing_cap_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.billing_cap.email}"
}

# ── Secret Manager: Gmail app password ───────────────────────────────────────

resource "google_secret_manager_secret" "gmail_password" {
  secret_id = "billing-cap-gmail-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "gmail_password" {
  secret      = google_secret_manager_secret.gmail_password.id
  secret_data = var.alert_email_password
}

# ── Cloud Function (2nd gen) ─────────────────────────────────────────────────

resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-billing-cap-src"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
}

data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../function"
  output_path = "${path.module}/.build/function.zip"
}

resource "google_storage_bucket_object" "function_zip" {
  name   = "function-${data.archive_file.function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_zip.output_path
}

resource "google_cloudfunctions2_function" "billing_cap" {
  name     = "billing-cap"
  location = var.region

  build_config {
    runtime     = "python312"
    entry_point = "disable_billing"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_zip.name
      }
    }
  }

  service_config {
    service_account_email = google_service_account.billing_cap.email
    min_instance_count    = 0
    max_instance_count    = 1
    timeout_seconds       = 60
    environment_variables = {
      GCP_PROJECT_ID     = var.project_id
      THRESHOLD_FRACTION = tostring(var.threshold_fraction)
      ALERT_EMAIL_TO     = var.alert_email_to
      ALERT_EMAIL_FROM   = var.alert_email_from
    }
    secret_environment_variables {
      key        = "ALERT_EMAIL_PASSWORD"
      project_id = var.project_id
      secret     = google_secret_manager_secret.gmail_password.secret_id
      version    = "latest"
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.billing_cap.id
    retry_policy   = "RETRY_POLICY_DO_NOT_RETRY"
  }
}

# ── Budget alert ─────────────────────────────────────────────────────────────

resource "google_billing_budget" "cap" {
  billing_account = var.billing_account_id
  display_name    = "${var.project_id} hard cap"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.monthly_budget_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    pubsub_topic                   = google_pubsub_topic.billing_cap.id
    disable_default_iam_recipients = false
  }
}
