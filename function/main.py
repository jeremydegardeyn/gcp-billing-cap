"""
Billing cap: disable GCP billing on a project when a budget threshold is hit.

Triggered by a Pub/Sub message from a GCP Budget alert.
"""

import base64
import json
import os

import googleapiclient.discovery
from google.auth import default

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
# Fraction of budget at which to kill billing (1.0 = 100%)
THRESHOLD_FRACTION = float(os.environ.get("THRESHOLD_FRACTION", "1.0"))


def disable_billing(event=None, context=None):
    """Pub/Sub Cloud Function entry point."""
    data = _parse_event(event)
    if data is None:
        print("Could not parse event payload")
        return

    cost_amount = float(data.get("costAmount", 0))
    budget_amount = float(data.get("budgetAmount", 1))
    fraction = cost_amount / budget_amount if budget_amount else 0

    print(
        f"costAmount={cost_amount} budgetAmount={budget_amount} "
        f"fraction={fraction:.2%} threshold={THRESHOLD_FRACTION:.2%}"
    )

    if fraction < THRESHOLD_FRACTION:
        print("Under threshold — no action taken")
        return

    billing_info = _get_billing_info()
    if not billing_info.get("billingEnabled"):
        print("Billing already disabled")
        return

    print(f"Threshold exceeded — disabling billing on {PROJECT_ID}")
    _set_billing_disabled()
    print("Billing disabled successfully")


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
