<!-- toc -->

- [Preface](#preface)
- [Overview](#overview)
  - [Key Features](#key-features)
- [Architecture](#architecture)
- [Part 1: Setup](#part-1-setup)
  - [Overview](#overview-1)
  - [Prerequisites](#prerequisites)
  - [Step 1: Azure AD Setup (one-time)](#step-1-azure-ad-setup-one-time)
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
  - [AWS Lambda: Embeddings Forwarder](#aws-lambda-embeddings-forwarder)
- [LLM Integration](#llm-integration)
  - [Cost Analysis](#cost-analysis)
    - [Understanding Token-Based Pricing](#understanding-token-based-pricing)
    - [Processing Costs](#processing-costs)
      - [Typical Interview Analysis](#typical-interview-analysis)
      - [Cost Breakdown (per transcript)](#cost-breakdown-per-transcript)
      - [Budget Planning](#budget-planning)
  - [Supported Embedding Models](#supported-embedding-models)
    - [OpenAI](#openai)
    - [AWS Bedrock](#aws-bedrock)
    - [Embedding Strategy](#embedding-strategy)
    - [Text Preprocessing for Embeddings](#text-preprocessing-for-embeddings)
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

This project uses Microsoft Graph API's webhook notifications to enable real-time processing of Teams meeting transcripts.

When a new transcript becomes available, Microsoft Graph sends an HTTP notification to our webhook endpoint. This triggers a serverless processing pipeline that retrieves the transcript, processes it using an LLM provider to generate embeddings, and stores them for later use.
Please see the [Architecture](#architecture) section below for more details.

The system maintains webhook subscriptions through automated renewal processes, ensuring continuous real-time notifications for new transcripts across the organization.

## Key Features

- Real-time transcript processing
- Secure authentication and data handling
- Scalable serverless architecture
- Automated subscription management

# Architecture

![Architecture Diagram](https://lucid.app/publicSegments/view/396bb585-25cf-441a-beee-c13dbd4453bd/image.jpeg)

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
   - Pinecone for embeddings

# Part 1: Setup

## Overview

This section is a setup for development:

1. [Azure AD Setup (one-time)](#step-1-azure-ad-setup-one-time) - Registers an application to access Teams data.
2. [Webhook Registration (+ Renewal)](#step-2-webhook-registration--renewal) - Sets up the connection between Teams and this service.

## Prerequisites

1. **Microsoft 365 Account** with Teams and ability to record meetings.
2. **Azure Account** (can use free tier) - Required for app registration.
3. **Node.js** installed on the development machine.
4. **AWS Account** - For hosting the webhook endpoint.

## Step 1: Azure AD Setup (one-time)

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

Find and save these values from the app registration "Overview" page and fill in [src/setup/.env](src/setup/.env):

- **Tenant ID**
- **Client ID**
- **Client Secret** (from the previous step)

## Step 2: Webhook Registration / Renewal

1. **Register Webhook**:

   One-time webhook setup with Microsoft Graph: Create a subscription in Microsoft Graph API to receive transcript notifications. Only one active subscription is needed - the script will check for existing subscriptions before creating a new one.

   [scripts/setup/webhook.ps1](scripts/setup/webhook.ps1)

   ```powershell
   ./scripts/setup/webhook.ps1 -mode Register
   ```

   Implementation: [src/setup/register-webhook-cli.js](src/setup/register-webhook-cli.js), [src/setup/core/subscription-manager.js](src/setup/core/subscription-manager.js), [src/setup/auth-cli.js](src/setup/auth-cli.js)

2. **Subscription Renewal**:

   The subscription is automatically renewed daily by the [src/setup/auto-renew-handler.js](src/setup/auto-renew-handler.js) Lambda function.

   For manual renewal if needed:

   ```powershell
   ./scripts/setup/webhook.ps1 -mode Renew
   ```

   Implementation: [src/setup/auto-renew-handler.js](src/setup/auto-renew-handler.js), [src/setup/renew-subscription-cli.js](src/setup/renew-subscription-cli.js)

## Staging / Production

For deploying to production or setting up additional organizations, refer to:
[teams-transcripts-to-Webhook-registration-summary.md](teams-transcripts-to-Webhook-registration-summary.md)

Note: The Azure AD app registration and permissions setup described above is a one-time development step. New organizations only need to grant consent to your existing app registration.

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

## AWS Lambda: Embeddings Forwarder

[src/runtime/embeddings-forwarder.js](src/runtime/embeddings-forwarder.js)

Forwards selected data from DynamoDB Streams to Pinecone vector database. Key responsibilities:

- Processes DynamoDB Stream events (INSERT and MODIFY) containing transcript data and embeddings.
- Extracts key fields including transcript text, candidate email, participants, timestamps, and embedding vectors.
- Truncates transcript text to stay within Pinecone metadata size limits (~15KB).
- Upserts vectors with metadata into Pinecone index for semantic search capabilities.
- Manages secure access to Pinecone credentials via AWS Secrets Manager.

# LLM Integration

While the examples below reference OpenAI's models, the architecture is designed to be model-agnostic. It supports integration with various LLM providers, including AWS Bedrock models, and other compatible services. See [Supported Embedding Models](#supported-embedding-models) for details.

## Cost Analysis

### Understanding Token-Based Pricing

This project uses OpenAI's text-embedding-ada-002 model (aka ada-002) for generating embeddings. The pricing structure is straightforward:

**Embedding Tokens** ($0.0001 / 1K tokens)

- Each token ≈ 4 characters in English
- Both input text and generated embeddings are counted in this price
- Very cost-effective for semantic search use cases
- Generates 1536-dimensional embedding vectors

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

## Supported Embedding Models

The system supports multiple embedding models through different providers:

### OpenAI

- **text-embedding-ada-002** (aka ada-002)
  - 1536-dimensional embeddings
  - 8K token context window
  - Best-in-class performance for semantic search
  - $0.0001 per 1K tokens

### AWS Bedrock

- **amazon.titan-embed-text-v1**

  - Native AWS solution
  - 8,192 token limit (~38,500 characters for English text)
  - Pay-as-you-go AWS pricing

- **cohere.embed-english-v3**

  - Supports up to 512K tokens
  - Optimized for English text

- **cohere.embed-multilingual-v3**
  - Supports up to 512K tokens
  - Handles multiple languages effectively

The model can be configured via the `EMBEDDING_MODEL` environment variable in the format:

- OpenAI models: `openai.ada-002`
- AWS models: `amazon.titan-embed-text-v1`, `cohere.embed-english-v3`, etc.

### Embedding Strategy

While it might seem intuitive to summarize text before embedding to capture key points, we recommend embedding the full transcript text directly because:

1. **Information Preservation**: Modern embedding models (especially with 1536 dimensions) are specifically trained to capture semantic relationships in high-dimensional space, preserving nuanced meaning
2. **Cost Efficiency**: Direct embedding is more cost-effective than running both summarization and embedding
3. **Search Flexibility**: Full text embeddings allow searching for specific details that might have been omitted in a summary
4. **Accuracy**: Summarization could introduce bias or lose important context that the embedding model would have captured

### Text Preprocessing for Embeddings

To optimize text before generating embeddings:

1. **Basic Cleanup**

   - Remove redundant whitespace and empty lines
   - Fix common transcription artifacts (repeated words, filler sounds)
   - Normalize text case when appropriate

2. **Chunking Strategy**
   - For long transcripts exceeding model limits:
     - Split at natural boundaries (speaker turns, topics)
     - Maintain context in each chunk
     - Consider overlap between chunks
   - Use model-specific token limits:
     - OpenAI ada-002: 8K tokens
     - Titan: 8,192 tokens
     - Cohere: 512K tokens

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

![Architecture Diagram](https://lucid.app/publicSegments/view/396bb585-25cf-441a-beee-c13dbd4453bd/image.jpeg)
