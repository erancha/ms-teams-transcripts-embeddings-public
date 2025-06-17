<!-- toc -->

- [Teams Transcripts to Webhook Lambda - Registration Summary](#teams-transcripts-to-webhook-lambda---registration-summary)
  - [Overview](#overview)
  - [Process](#process)
    - [Step 1: Azure AD App Registration (one time)](#step-1-azure-ad-app-registration-one-time)
    - [Step 2: Per-tenant (each Teams organization) setup](#step-2-per-tenant-each-teams-organization-setup)
      - [Step 2.1: Grant Admin Consent](#step-21-grant-admin-consent)
      - [Step 2.2: Configure Teams Access Policy](#step-22-configure-teams-access-policy)
      - [Step 2.3: Webhook registration for transcript notifications](#step-23-webhook-registration-for-transcript-notifications)
  - [Summary](#summary)

<!-- tocstop -->

# Teams Transcripts to Webhook Lambda - Registration Summary

## Overview

This document outlines the process for registering the application to send Microsoft Teams transcripts to a webhook lambda across multiple Teams accounts. The setup involves:

1. [Azure AD app registration and webhook setup](#step-1-azure-ad-app-registration-one-time) (one time)
   - App registration with required permissions
   - Webhook registration for transcript notifications
2. [Per-tenant (each Teams organization) setup](#step-2-per-tenant-each-teams-organization-setup) (for each Teams organization):
   - [Admin consent](#step-21-grant-admin-consent)
   - [Teams access policy configuration](#step-22-configure-teams-access-policy)
   - [Share tenant ID for webhook registration](#step-23-share-tenant-id-for-webhook-registration)

ℹ️ Organizations only need to complete the per-tenant setup - they use our existing app registration.

ℹ️ After completing steps 1 and 2, we will handle webhook registration for each tenant. They only need to share their tenant ID with us.

## Process

### Step 1: Azure AD App Registration (one time)

This step was already completed during initial app development. The app registration exists in the development's Azure AD tenant with all necessary permissions configured. No additional permission configuration is needed for new organizations.

### Step 2: Per-tenant (each Teams organization) setup

#### Step 2.1: Grant Admin Consent

1. Admin clicks the following link and prompted to sign in with Microsoft 365 admin credentials
2. Admin reviews and accepts the permissions

```
https://login.microsoftonline.com/common/adminconsent?client_id=1a201a82-3f30-4357-b17f-342a6648394b
```

#### Step 2.2: Configure Teams Access Policy

The tenant admin must run a PowerShell script with admin credentials to allow transcript access:

[scripts/setup/teams-app-access-policy.ps1](scripts/setup/teams-app-access-policy.ps1)

```powershell
./scripts/setup/teams-app-access-policy.ps1 -tenantId <UUID>
```

- Installs Teams PowerShell module if needed
- Creates application access policy for transcripts
- Grants the policy globally

Verification:

```powershell
Get-CsApplicationAccessPolicy -Identity "TranscriptAccess"
```

#### Step 2.3: Share tenant ID for webhook registration

After completing the admin consent and Teams access policy setup:

1. Locate your tenant ID (Directory ID, a UUID) from Azure Active Directory
2. Share the tenant ID with us
3. We will register and manage the webhook subscription for your tenant using our centralized management system

No additional setup is required on your end. We handle all webhook registration, renewal, and management using our application credentials.

## Summary

- **Simple and scalable** approach for multiple Teams organizations
- **One app registration** in Azure AD, with **one common consent URL** for all Teams tenants
- Both consent and policy are persistent and don't need to be repeated
- **Same Lambda webhook endpoint** across all Teams tenants, differentiates between tenants using tenant ID in webhook payload
