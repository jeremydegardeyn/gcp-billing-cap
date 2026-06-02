# gcp-billing-cap

Automatically disables GCP billing on a project when a spend threshold is reached, and sends an email alert. This follows the [Google-recommended approach for capping GCP costs](https://cloud.google.com/billing/docs/how-to/notify#cap_disable_billing_to_stop_usage).

## How it works

```
GCP Budget (forecasted spend)
        │
        │  Pub/Sub notification at 50%, 80%, 100%
        ▼
  Pub/Sub Topic (billing-cap)
        │
        ▼
  Cloud Function (billing-cap)
        │
        ├─ under threshold → log only, no action
        │
        └─ at/over threshold → disable billing on project
                                + send email alert
```

1. **GCP Budget** monitors forecasted monthly spend for the project. At 50% and 80% it fires an alert email to billing admins. At 100% it publishes a Pub/Sub message.
2. **Pub/Sub topic** receives the budget notification and triggers the Cloud Function.
3. **Cloud Function** checks whether the spend fraction has hit the threshold. If so, it detaches the billing account from the project — stopping all GCP services — and sends an email alert via SMTP.

> **Note:** Detaching billing stops all running GCP resources immediately. To restore service, manually re-attach the billing account in the [GCP console](https://console.cloud.google.com/billing/projects). Re-enabling is intentionally not automated.

> **Latency:** GCP budget data has roughly 24-hour latency, so there is a window where spend could exceed the cap before the function fires.

## Prerequisites

Enable the required APIs on your project:

```bash
gcloud services enable \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  billingbudgets.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  --project=YOUR_PROJECT_ID
```

## Deploy

1. Copy the example tfvars and fill in your values:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

```hcl
project_id         = "your-gcp-project-id"
billing_account_id = "XXXXXX-XXXXXX-XXXXXX"   # Billing > Account overview
monthly_budget_usd = 50
threshold_fraction = 1.0
alert_email_to     = "you@example.com"
smtp_user          = "your-gmail@gmail.com"
smtp_pass          = "xxxx xxxx xxxx xxxx"     # Gmail app password
smtp_from_email    = "your-gmail@gmail.com"
smtp_from_name     = "Your Name"
```

> For `smtp_pass`, use a [Gmail App Password](https://myaccount.google.com/apppasswords) — not your regular password. Requires 2FA to be enabled.

2. Deploy:

```bash
cd terraform
terraform init
terraform apply
```

3. After apply, grant the service account billing account access — this cannot be done via Terraform. In the GCP console go to **Billing > Account Management > Add Principal** and assign:

- **Principal:** `billing-cap-fn@YOUR_PROJECT_ID.iam.gserviceaccount.com`
- **Role:** Billing Account Costs Manager

## Dry run mode

By default the billing detachment is commented out in `function/main.py` — the function will log what it *would* do and send the alert email, but won't actually kill billing. To go live, uncomment this line:

```python
# _set_billing_disabled()  # TODO: uncomment to enable hard cutoff
```

Then redeploy by running `terraform apply` again (the function zip hash will change and trigger a redeployment).

## Configuration

| Variable | Default | Description |
|---|---|---|
| `project_id` | — | GCP project to protect |
| `billing_account_id` | — | GCP billing account ID |
| `monthly_budget_usd` | — | Monthly cap in USD |
| `threshold_fraction` | `1.0` | Fraction of budget that triggers the kill (1.0 = 100%) |
| `region` | `us-central1` | Cloud Function deployment region (does not affect budget scope) |
| `alert_email_to` | — | Address to receive kill alerts |
| `smtp_host` | `smtp.gmail.com` | SMTP host |
| `smtp_port` | `587` | SMTP port (STARTTLS) |
| `smtp_user` | — | SMTP username |
| `smtp_pass` | — | SMTP password (stored in Secret Manager) |
| `smtp_from_email` | — | From address |
| `smtp_from_name` | `DataDinosaur` | From display name |
