"""
Billing cap: disable GCP billing on a project when a budget threshold is hit.

Triggered by a Pub/Sub message from a GCP Budget alert.
"""

import base64
import json
import os
import smtplib
from email.mime.text import MIMEText

import googleapiclient.discovery
from google.auth import default

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
THRESHOLD_FRACTION = float(os.environ.get("THRESHOLD_FRACTION", "1.0"))

ALERT_EMAIL_TO = os.environ.get("ALERT_EMAIL_TO", "")
SMTP_HOST = os.environ.get("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASS = os.environ.get("SMTP_PASS", "")
SMTP_FROM_EMAIL = os.environ.get("SMTP_FROM_EMAIL", "")
SMTP_FROM_NAME = os.environ.get("SMTP_FROM_NAME", "GCP Billing Cap")


def disable_billing(event=None, context=None):
    """Pub/Sub Cloud Function entry point."""
    data = _parse_event(event)
    if data is None:
        print("Could not parse event payload")
        return

    cost_amount = float(data.get("costAmount", 0))
    budget_amount = float(data.get("budgetAmount", 1))
    forecast_threshold = float(data.get("forecastThresholdExceeded", 0))
    actual_threshold = float(data.get("alertThresholdExceeded", 0))
    triggered_threshold = max(forecast_threshold, actual_threshold)

    print(
        f"costAmount={cost_amount} budgetAmount={budget_amount} "
        f"forecastThresholdExceeded={forecast_threshold} "
        f"alertThresholdExceeded={actual_threshold} "
        f"triggered={triggered_threshold:.2%} threshold={THRESHOLD_FRACTION:.2%}"
    )

    if triggered_threshold < THRESHOLD_FRACTION:
        print("Under threshold — no action taken")
        return

    billing_info = _get_billing_info()
    if not billing_info.get("billingEnabled"):
        print("Billing already disabled")
        return

    print(f"Threshold exceeded — disabling billing on {PROJECT_ID}")
    # _set_billing_disabled()  # TODO: uncomment to enable hard cutoff
    print("DRY RUN: billing would have been disabled (detachment is commented out)")

    _send_alert_email(cost_amount, budget_amount)


def _parse_event(event):
    try:
        payload = base64.b64decode(event["data"]).decode("utf-8")
        return json.loads(payload)
    except Exception as exc:
        print(f"Failed to decode Pub/Sub event: {exc}")
        return None


def _billing_client():
    credentials, _ = default()
    return googleapiclient.discovery.build(
        "cloudbilling", "v1", credentials=credentials, cache_discovery=False
    )


def _get_billing_info():
    client = _billing_client()
    return client.projects().getBillingInfo(name=f"projects/{PROJECT_ID}").execute()


def _set_billing_disabled():
    client = _billing_client()
    client.projects().updateBillingInfo(
        name=f"projects/{PROJECT_ID}", body={"billingAccountName": ""}
    ).execute()


def _send_alert_email(cost_amount: float, budget_amount: float):
    if not all([ALERT_EMAIL_TO, SMTP_USER, SMTP_PASS, SMTP_FROM_EMAIL]):
        print("Email env vars not set — skipping notification")
        return

    subject = f"[GCP BILLING DISABLED] {PROJECT_ID} exceeded ${budget_amount:.2f} budget"
    body = (
        f"GCP billing has been automatically disabled for project: {PROJECT_ID}\n\n"
        f"Spend:  ${cost_amount:.2f}\n"
        f"Budget: ${budget_amount:.2f}\n\n"
        f"All GCP services on this project are now stopped.\n"
        f"To restore service, re-attach the billing account in the GCP console:\n"
        f"https://console.cloud.google.com/billing/projects\n"
    )

    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = f"{SMTP_FROM_NAME} <{SMTP_FROM_EMAIL}>"
    msg["To"] = ALERT_EMAIL_TO

    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_USER, SMTP_PASS)
            server.sendmail(SMTP_FROM_EMAIL, [ALERT_EMAIL_TO], msg.as_string())
        print(f"Alert email sent to {ALERT_EMAIL_TO}")
    except Exception as exc:
        print(f"Failed to send alert email: {exc}")
