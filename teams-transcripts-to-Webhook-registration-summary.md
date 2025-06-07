<!-- toc -->

- [Teams Transcripts to Webhook Lambda - Registration Summary](#teams-transcripts-to-webhook-lambda---registration-summary)
  - [Overview](#overview)
  - [Process](#process)
    - [Step 1: Azure AD App Registration (one time)](#step-1-azure-ad-app-registration-one-time)
    - [Step 2: Per-Teams-Tenant Admin Consent](#step-2-per-teams-tenant-admin-consent)
  - [Summary](#summary)

<!-- tocstop -->

# Teams Transcripts to Webhook Lambda - Registration Summary

## Overview

This document summarizes the process for registering an application to send Microsoft Teams transcripts to a webhook lambda across multiple Teams accounts.

**Azure AD application registration (one time** per application - not per Teams account)

- Registered once per Azure AD tenant.
- The app registration defines permissions and webhook endpoint globally.

**Per-Teams-Tenant registration**

1. **Admin consent** - Tenant admin must grant consent for the app.
2. **Minimal Teams Subscription** - Business Basic (https://www.microsoft.com/en-us/microsoft-teams/compare-microsoft-teams-business-options)

## Process

### Step 1: Azure AD App Registration (one time)

Create single app registration with required permissions in your Azure AD tenant:

- `OnlineMeetings.Read.All` (for meeting transcripts)
- `CallRecords.Read.All` (for call records)

### Step 2: Per-Teams-Tenant Admin Consent

**Recommended Approach - Common Consent URL:**

```
https://login.microsoftonline.com/common/adminconsent?client_id={your-app-id}
```

1. Send the common consent URL to each Teams tenant admin
2. Admin clicks the link and signs in with their admin account
3. Microsoft automatically detects their tenant
4. Admin reviews and accepts the permissions
5. Consent is granted for their specific tenant

## Summary

- **Simple and scalable** approach for multiple Teams organizations
- **One app registration** in Azure AD, with **one common consent URL** for all Teams tenants
- **Each Teams tenant admin** must grant consent; Consent is persistent - once granted, doesn't need to be repeated; Consent status can be verified via Microsoft Graph API
- **Same Lambda webhook endpoint** across all Teams tenants, differentiates between tenants using tenant ID in webhook payload
