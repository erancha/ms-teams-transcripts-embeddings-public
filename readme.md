<!-- toc -->

- [Preface](#preface)
- [Overview](#overview)
  - [Key Features](#key-features)
- [Architecture](#architecture)
- [Part 1: Development Setup](#part-1-development-setup)
  - [Overview](#overview-1)
  - [Prerequisites](#prerequisites)
  - [Step 1: Azure AD Setup (One-time)](#step-1-azure-ad-setup-one-time)
    - [Create App Registration](#create-app-registration)
    - [Configure API Permissions](#configure-api-permissions)
    - [Create Client Secret](#create-client-secret)
    - [Collect Configuration Values](#collect-configuration-values)
  - [Step 2: Webhook Registration / Renewal](#step-2-webhook-registration--renewal)
  - [Staging / Production](#staging--production)
- [Part 2: Runtime](#part-2-runtime)
  - [Using the Service](#using-the-service)
  - [AWS Lambda: WebHook handler](#aws-lambda-webhook-handler)
  - [AWS Lambda: Transcript Processor](#aws-lambda-transcript-processor)
- [LLM Integration](#llm-integration)
  - [Cost Analysis](#cost-analysis)
    - [Understanding Token-Based Pricing](#understanding-token-based-pricing)
    - [Processing Costs](#processing-costs)
      - [Typical Interview Analysis](#typical-interview-analysis)
      - [Cost Breakdown (per transcript)](#cost-breakdown-per-transcript)
      - [Budget Planning](#budget-planning)
  - [Prompt Engineering Guide](#prompt-engineering-guide)
    - [Core Principles](#core-principles)
    - [Example Prompt Template](#example-prompt-template)
    - [Token Optimization](#token-optimization)
- [Appendix (phase 2+): Webhook Security](#appendix-phase-2-webhook-security)
  - [Signature Verification](#signature-verification)
  - [Mutual TLS (mTLS)](#mutual-tls-mtls)
  - [IP Whitelisting](#ip-whitelisting)
  - [Token-Based Authentication](#token-based-authentication)
  - [HTTPS Requirements](#https-requirements)
  - [Additional Hardening Measures](#additional-hardening-measures)
- [Appendix (phase 2+): Whatsapp](#appendix-phase-2-whatsapp)
  - [Architecture](#architecture-1)

<!-- tocstop -->

# Preface

Requirements: To process transcripts from Microsoft Teams meeting into embeddings and store them for AI-powered analysis (at this point, the project ignores the usage of the embeddings - the current focus is to generate the embeddings).

# Overview

This project uses Microsoft Graph API's webhook notifications to capture new transcripts as they become available, process them using an LLM provider, and store the resulting embeddings for later use.

## Key Features

- Real-time transcript processing
- Secure authentication and data handling
- Scalable serverless architecture
- Automated subscription management
- Token-optimized prompt engineering

# Architecture

![Architecture Diagram](https://lucid.app/publicSegments/view/c2473c07-a7c8-4ecc-8da1-2cb63f24f7ea/image.jpeg)

1. **Microsoft Teams Integration**

   - Uses Graph API Change Notifications (webhooks)
   - Real-time notifications when transcripts are available
   - Secure authentication via Azure AD

2. **Processing Pipeline**

   - AWS Lambda for webhook handling
   - SQS for reliable message queuing and retry handling
   - Dead-letter queue (DLQ) for failed message handling
   - Separate processor for transcript analysis
   - AWS Bedrock or direct OpenAI API for embedding generation

3. **Storage Layer**
   - S3 for raw transcript archival
   - DynamoDB for structured data

# Part 1: Development Setup

## Overview

This section is a setup for development:

1. Azure AD Setup (one-time) - Registers an application to access Teams data.
2. Webhook Registration (+ /Renewal) - Sets up the connection between Teams and this service.

## Prerequisites

1. **Microsoft 365 Account** with Teams and ability to record meetings.
2. **Azure Account** (can use free tier) - Required for app registration.
3. **Node.js** installed on the development machine.
4. **AWS Account** - For hosting the webhook endpoint

## Step 1: Azure AD Setup (One-time)

### Create App Registration

1. Go to [Azure Portal](https://portal.azure.com) and sign in
2. Navigate to Azure Active Directory → App registrations
3. Click "New registration"
4. Fill in:
   - **Name**: "Teams Transcript Processor"
   - **Supported account types**: "Accounts in this organizational directory only"
   - **Redirect URI**: Leave blank
5. Click "Register"

### Configure API Permissions

1. In your new app registration, go to "API permissions"
2. Click "Add a permission" → Microsoft Graph → Application permissions
3. Add these permissions:
   - `CallRecords.Read.All` - For accessing call recordings
   - `OnlineMeetings.Read.All` - For meeting information
   - `OnlineMeetingTranscript.Read.All` - For transcript access
4. Click "Grant admin consent"

### Create Client Secret

1. Go to "Certificates & secrets"
2. Click "New client secret"
3. Set description and expiration (e.g., 12 months)
4. **IMPORTANT**: Copy and save the secret value immediately - you won't see it again

### Collect Configuration Values

Find and save these values from the app registration "Overview" page and fill in [scripts/setup/.env](scripts/setup/.env):

- **Tenant ID**
- **Client ID**
- **Client Secret** (from previous step)

## Step 2: Webhook Registration / Renewal

1. **Register Webhook**:

   One-time webhook setup with Microsoft Graph: Create a subscription in Microsoft Graph API to receive transcript notifications

   [scripts/setup/webhook.ps1](scripts/setup/webhook.ps1)

   ```powershell
   ./scripts/setup/webhook.ps1 -mode Register
   ```

   [src/setup/register-webhook.js](src/setup/register-webhook.js) , [src/setup/subscription.js](src/setup/subscription.js) , [src/setup/auth.js](src/setup/auth.js)

2. **Configure Auto-renewal**:

   Set this up as a scheduled task (daily) to renew the subscription

   [scripts/setup/webhook.ps1](scripts/setup/webhook.ps1)

   ```powershell
   ./scripts/setup/webhook.ps1 -mode Renew
   ```

   [src/setup/renew-subscription.js](src/setup/renew-subscription.js)

## Staging / Production

This section summarizes the steps for using the solution in staging and production:

[teams-transcripts-to-Webhook-registration-summary.md](teams-transcripts-to-Webhook-registration-summary.md)

# Part 2: Runtime

## Using the Service

1. Start a **Teams Meeting** with transcription (either set up in the meeting or during the meeting: Click the "More actions" (...) button, select "Start recording", in the recording options, enable "Transcription").
2. When the meeting ends, the transcript will be automatically processed.

## AWS Lambda: WebHook handler

[src/runtime/webhook-handler.js](src/runtime/webhook-handler.js)

Receives and validates Teams webhook notifications and queus them for processing.
Key responsibilities:

- Validates incoming Microsoft webhook requests.
- Queues transcripts for asynchronous processing.
- Handles error cases and retries.

## AWS Lambda: Transcript Processor

[src/runtime/transcript-processor.js](src/runtime/transcript-processor.js)

Processes queued Teams webhook notifications. Key responsibilities:

- Retrieves call records from Microsoft Graph API.
- Downloads and parses VTT transcripts.
- Stores raw transcripts in S3 for archival.
- Generates embeddings.
- Stores processed data in DynamoDB.

# LLM Integration

While the examples below reference OpenAI's models, the architecture is designed to be model-agnostic. It supports integration with various LLM providers, including AWS Bedrock models, Amazon SageMaker endpoints, and other compatible services.

## Cost Analysis

### Understanding Token-Based Pricing

OpenAI's API pricing structure has three components:

1. **Input Tokens** ($0.0010 / 1K tokens)

   - Raw transcript text
   - System prompts and instructions
   - Each token ≈ 4 characters in English
   - Primary cost driver (~75% of total)

2. **Cached Input** ($0.0002 / 1K tokens)

   - System prompts and templates
   - Reused across multiple transcripts
   - Minimal impact on total cost (~5%)

3. **Output Tokens** ($0.0020 / 1K tokens)
   - Structured candidate data
   - Generated embeddings
   - ~20% of total processing cost

### Processing Costs

#### Typical Interview Analysis

30-minute interview contains:

- Words: 4,500-7,500 (150-250 wpm)
- Tokens: 3,400-5,600 tokens
- Processing time: 15-25 seconds

#### Cost Breakdown (per transcript)

- Input processing: $0.0034-$0.0056
- Embedding generation: $0.0007-$0.0011
- Total cost: $0.0041-$0.0067

#### Budget Planning

- Monthly (100 interviews): $0.41-$0.67
- Quarterly (300 interviews): $1.23-$2.01
- Annual (1,200 interviews): $4.92-$8.04

## Prompt Engineering Guide

### Core Principles

1. **Structured Instructions**

   - Break complex tasks into clear steps
   - Specify exact data points to extract
   - Define output format (JSON structure)
   - Include validation requirements

2. **Context Setting**

   - Specify interview/meeting type
   - Define participant roles
   - Indicate industry context
   - Note any special terminology

3. **Format Control**
   - Use consistent JSON schema
   - Specify data types for fields
   - Define enumerated values
   - Include validation rules

### Example Prompt Template

```text
Analyze this initial recruiter screening call transcript.

Context:
- Interview type: Initial screening call
- Purpose: Assess candidate fit and requirements
- Focus areas: Experience, motivations, expectations

Extract the following information:
1. Career history
   - Current/previous roles
   - Reasons for transitions
   - Key achievements

2. Job preferences
   - Desired role type
   - Work arrangement (remote/hybrid/onsite)
   - Company culture preferences

3. Practical requirements
   - Notice period/availability
   - Salary expectations
   - Location/relocation flexibility

4. Technical background
   - Self-reported skill areas
   - Recent project types
   - Tools/technologies mentioned

Provide structured output focusing on candidate's narrative and stated preferences.
```

### Token Optimization

1. **Input Efficiency**

   - Clear, concise instructions
   - Reusable system prompts
   - Minimal repetition

2. **Output Control**
   - Structured data over prose
   - Specific field constraints
   - Enumerated response options

# Appendix (phase 2+): Webhook Security

Webhooks face unique security challenges since they're essentially publicly accessible endpoints that accept incoming HTTP requests, making them potential attack vectors. Here are the main security mechanisms used:

## Signature Verification

The most common approach is cryptographic signature verification. The webhook sender generates a signature using a shared secret key and includes it in the request headers. The receiver recalculates the signature and compares it to verify authenticity.

Common implementations include HMAC-SHA256 signatures (used by GitHub, Stripe, and others) where the sender creates a hash of the payload using the shared secret, and the receiver performs the same calculation to verify the request hasn't been tampered with.

## Mutual TLS (mTLS)

For high-security environments, mutual TLS provides strong authentication where both the client (webhook sender) and server (webhook receiver) authenticate each other using certificates. This ensures encrypted communication and verifies the identity of both parties.

## IP Whitelisting

Many webhook providers publish lists of IP addresses from which they send webhooks. Receivers can configure their firewalls or application logic to only accept requests from these known IP ranges, though this approach has limitations since IP ranges can change.

## Token-Based Authentication

Some systems use bearer tokens or API keys included in request headers. The webhook sender includes a pre-shared token that the receiver validates. While simpler to implement, this is generally less secure than signature verification since tokens can be intercepted more easily.

## HTTPS Requirements

All webhook traffic should use HTTPS to encrypt data in transit. Many webhook providers will refuse to deliver to non-HTTPS endpoints, and receivers should reject any HTTP requests.

## Additional Hardening Measures

Webhook endpoints often implement rate limiting to prevent abuse, request size limits to avoid payload-based attacks, and timeout configurations to prevent resource exhaustion. Many also validate the Content-Type header and implement replay attack protection by including timestamps in signature calculations or maintaining request logs.

The combination of HTTPS transport encryption with HMAC signature verification represents the current best practice for most webhook implementations, providing both confidentiality and authenticity without requiring complex certificate management.

# Appendix (phase 2+): Whatsapp

## Architecture

Note: The architecture is designed with extensibility in mind, allowing for integration with various messaging and communication platforms beyond MS teams, for example Whatsapp. The core components and processing pipeline (Webhook Handler, SQS, Transcript Processor) should be designed to be adaptable to support additional data sources while maintaining consistent data processing and analysis capabilities.

![Architecture Diagram](https://lucid.app/publicSegments/view/c2473c07-a7c8-4ecc-8da1-2cb63f24f7ea/image.jpeg)
