# AI Digital Twin

> A production-grade, cloud-deployed AI chatbot that acts as a living digital representation of **Raktima Barman** — Data Scientist & AI/ML Engineer at AB InBev GCC. Ask it anything about her background, expertise, projects, or career.

---

## Table of Contents

- [What Is This?](#what-is-this)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Local Development](#local-development)
- [Infrastructure with Terraform](#infrastructure-with-terraform)
- [Deploying to AWS](#deploying-to-aws)
- [Environment Variables](#environment-variables)
- [API Reference](#api-reference)
- [Project Structure](#project-structure)
- [Destroy Guide](#️-destroy-guide-read-this)

---

## What Is This?

The **AI Digital Twin** is a personal AI agent trained on real professional context — LinkedIn profile, career summary, communication style, and domain expertise. When you chat with it, you're talking to an AI that speaks *as* Raktima: with her tone, her opinions, her actual accomplishments.

**Why build this?**
This project is a hands-on learning exercise for AWS cloud services, serverless architecture, and Infrastructure as Code — built while self-studying AWS. The goal is to learn by shipping something real.

**What it can do:**
- Answer questions about Raktima's professional background and skills
- Discuss her projects in GenAI, MLOps, Computer Vision, and NLP
- Maintain multi-turn conversations with persistent memory (S3-backed)
- Run entirely serverless on AWS — no always-on server costs

---

## Architecture

```
User Browser
     │
     ▼
┌─────────────────────┐
│  CloudFront (CDN)   │  ← HTTPS, global edge caching
└─────────────────────┘
     │
     ▼
┌─────────────────────┐
│  S3 (Frontend)      │  ← Static Next.js build
└─────────────────────┘

User types message → API Gateway (HTTP API)
                           │
                           ▼
                    ┌─────────────┐
                    │   Lambda    │  ← FastAPI via Mangum
                    │  (Python)   │
                    └─────────────┘
                       │        │
            ┌──────────┘        └──────────┐
            ▼                              ▼
  ┌──────────────────┐         ┌──────────────────┐
  │  AWS Bedrock     │         │   S3 (Memory)    │
  │  Amazon Nova     │         │  Conversation    │
  │  (LLM)          │         │  History (JSON)  │
  └──────────────────┘         └──────────────────┘
```

**Request flow:**
1. User sends a message from the Next.js chat UI
2. API Gateway routes it to the Lambda function
3. Lambda loads the conversation history from S3
4. The personal context prompt (facts, summary, style) is injected
5. AWS Bedrock (Amazon Nova) generates the response
6. Conversation is saved back to S3
7. Response is returned to the browser

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Frontend** | Next.js 16, React 19, TypeScript, Tailwind CSS 4 |
| **Backend** | FastAPI, Python 3.14, Mangum (ASGI → Lambda) |
| **AI / LLM** | AWS Bedrock — Amazon Nova Lite |
| **Compute** | AWS Lambda (serverless, x86_64) |
| **API** | AWS API Gateway (HTTP API v2) |
| **Storage** | AWS S3 (frontend static files + conversation memory) |
| **CDN** | AWS CloudFront |
| **IaC** | Terraform >= 1.0, AWS Provider ~6.0 |
| **Build** | Docker (Lambda package), uv (Python deps), npm |
| **Optional** | AWS ACM (SSL), Route53 (custom domain) |

---

## Prerequisites

Make sure you have all of these installed and configured before starting.

### Tools Required

| Tool | Purpose | Version |
|---|---|---|
| [AWS CLI](https://aws.amazon.com/cli/) | Deploy and manage AWS resources | v2+ |
| [Terraform](https://developer.hashicorp.com/terraform/install) | Provision infrastructure | >= 1.0 |
| [Docker](https://www.docker.com/products/docker-desktop/) | Build Lambda package | Any recent |
| [Python](https://www.python.org/downloads/) | Run backend locally | 3.14+ |
| [uv](https://docs.astral.sh/uv/getting-started/installation/) | Fast Python package manager | Latest |
| [Node.js](https://nodejs.org/) | Build and run frontend | >= 20 |

### AWS Setup

1. **Create an AWS account** if you don't have one
2. **Configure CLI credentials:**
   ```bash
   aws configure
   # Enter: Access Key ID, Secret Access Key, Region (e.g. ap-southeast-2), output format (json)
   ```
3. **Enable AWS Bedrock model access:**
   - Go to AWS Console → Bedrock → Model access
   - Request access to **Amazon Nova Lite** (`amazon.nova-lite-v1:0`)
   - Wait for approval (usually instant for Nova models)

---

## Local Development

Run the backend and frontend on your machine without any AWS infrastructure.

### 1. Clone and configure

```bash
git clone <repo-url>
cd AI-Digital-Twin
```

Create a `.env` file at the project root:

```env
DEFAULT_AWS_REGION=ap-southeast-2
AWS_ACCOUNT_ID=your-account-id
BEDROCK_MODEL_ID=amazon.nova-lite-v1:0
CORS_ORIGINS=http://localhost:3000
PROJECT_NAME=twin
```

### 2. Start the backend

```bash
cd backend
uv sync                              # install dependencies
uv run uvicorn server:app --reload --port 8000
```

The API will be available at `http://localhost:8000`. Test it:

```bash
curl http://localhost:8000/health
```

> **Note:** In local mode, conversation history is stored in `/memory/*.json` files instead of S3.

### 3. Start the frontend

```bash
cd frontend
npm install
npm run dev
```

Open `http://localhost:3000` in your browser. The chat interface connects to `http://localhost:8000` by default.

---

## Infrastructure with Terraform

Terraform provisions all the AWS resources needed for production. Here's exactly how it works and what gets created.

### What Terraform Creates

```
Lambda Function          → runs the FastAPI backend
API Gateway (HTTP API)   → public HTTPS endpoint for the Lambda
S3 Bucket (memory)       → stores conversation history JSON files (private)
S3 Bucket (frontend)     → hosts the static Next.js build (public read)
CloudFront Distribution  → serves the frontend with HTTPS and edge caching
IAM Role + Policies      → grants Lambda access to Bedrock, S3, CloudWatch
```

### Terraform Variables

| Variable | Default | Description |
|---|---|---|
| `project_name` | *(required)* | Prefix for all AWS resource names (lowercase, hyphens only) |
| `environment` | *(required)* | One of: `dev`, `test`, `prod` |
| `bedrock_model_id` | `amazon.nova-micro-v1:0` | The Bedrock model to use |
| `lambda_timeout` | `60` | Lambda max execution time (seconds) |
| `api_throttle_burst_limit` | `10` | Max concurrent API requests |
| `api_throttle_rate_limit` | `5` | Sustained requests per second |
| `use_custom_domain` | `false` | Attach a custom domain via Route53 + ACM |
| `root_domain` | `""` | Your domain (e.g. `example.com`), required if above is `true` |

### Step-by-Step Terraform Usage

**Step 1 — Initialize Terraform**

Downloads the AWS provider plugin and sets up the backend. Run this once per clone.

```bash
cd terraform
terraform init
```

**Step 2 — Create a workspace**

Workspaces let you maintain separate `dev`, `test`, and `prod` environments from the same Terraform code with isolated state files.

```bash
terraform workspace new dev
# or switch to an existing one:
terraform workspace select dev
```

**Step 3 — Preview what will be created**

Always run `plan` before `apply`. It shows you exactly what Terraform intends to create, change, or destroy — with no side effects.

```bash
terraform plan \
  -var="project_name=twin" \
  -var="environment=dev"
```

Read the output carefully. Lines with `+` are new resources being created.

**Step 4 — Apply the infrastructure**

This actually creates the AWS resources. It will prompt for confirmation unless `--auto-approve` is used.

```bash
terraform apply \
  -var="project_name=twin" \
  -var="environment=dev"
```

Type `yes` when prompted. This takes roughly 2–5 minutes (CloudFront takes longest).

**Step 5 — Read the outputs**

After apply, Terraform prints the URLs you need:

```
api_gateway_url      = "https://xxxxxxxx.execute-api.ap-southeast-2.amazonaws.com"
cloudfront_url       = "https://dxxxxxxxxx.cloudfront.net"
s3_frontend_bucket   = "twin-dev-frontend-222767226474"
s3_memory_bucket     = "twin-dev-memory-222767226474"
lambda_function_name = "twin-dev-api"
```

You can retrieve these any time with:

```bash
terraform output
```

---

## Deploying to AWS

Use the provided scripts to build and deploy everything in one command.

### Windows (PowerShell)

```powershell
.\scripts\deploy.ps1 -Environment dev -ProjectName twin
```

### Linux / macOS (Bash)

```bash
bash scripts/deploy.sh dev twin
```

**What the script does:**
1. Builds the Lambda deployment package using Docker
2. Runs `terraform init` + `terraform apply`
3. Builds the Next.js frontend (`npm run build`)
4. Uploads the static build to S3 (`aws s3 sync`)
5. Prints the final CloudFront and API URLs

After deployment, open the CloudFront URL in your browser and start chatting.

---

## Environment Variables

### Backend (`.env` at project root)

| Variable | Example | Description |
|---|---|---|
| `DEFAULT_AWS_REGION` | `ap-southeast-2` | AWS region for Bedrock and S3 |
| `AWS_ACCOUNT_ID` | `222767226474` | Your 12-digit AWS account ID |
| `BEDROCK_MODEL_ID` | `amazon.nova-lite-v1:0` | Bedrock model identifier |
| `CORS_ORIGINS` | `http://localhost:3000` | Allowed frontend origins (comma-separated) |
| `PROJECT_NAME` | `twin` | Used to name S3 buckets and resources |
| `USE_S3` | `true` | Use S3 for memory (`true`) or local files (`false`) |
| `S3_BUCKET` | `twin-dev-memory-...` | S3 bucket name (auto-set by deploy script) |

### Frontend

| Variable | Default | Description |
|---|---|---|
| `NEXT_PUBLIC_API_URL` | `http://localhost:8000` | Backend API URL (auto-set by deploy script for production) |

---

## API Reference

### `GET /`
Health check. Returns service info and storage mode.

### `GET /health`
Returns Bedrock model ID and whether S3 memory is active.

### `POST /chat`

Send a message to the digital twin.

**Request:**
```json
{
  "message": "What are you working on at AB InBev?",
  "session_id": "optional-uuid-for-conversation-continuity"
}
```

**Response:**
```json
{
  "response": "Great question! Right now I'm leading...",
  "session_id": "3f1a2b9c-..."
}
```

### `GET /conversation/{session_id}`
Returns the full message history for a session as a JSON array.

---

## Project Structure

```
AI-Digital-Twin/
│
├── backend/                    # Python FastAPI backend
│   ├── server.py              # Main app: /chat endpoint, memory, Bedrock calls
│   ├── context.py             # Builds the system prompt from personal data
│   ├── resources.py           # Loads data files (PDF, JSON, TXT)
│   ├── lambda_handler.py      # Wraps FastAPI with Mangum for Lambda
│   ├── deploy.py              # Docker-based Lambda package builder
│   ├── requirements.txt       # Python deps for Lambda environment
│   └── data/
│       ├── facts.json         # Name, role, education, specialties
│       ├── summary.txt        # Career narrative and key accomplishments
│       ├── style.txt          # Tone and communication guidelines
│       └── linkedin.pdf       # Full LinkedIn profile (parsed at runtime)
│
├── frontend/                  # Next.js / React frontend
│   ├── app/
│   │   ├── layout.tsx         # Root HTML layout
│   │   └── page.tsx           # Renders the chat interface
│   ├── components/
│   │   └── twin.tsx           # Chat UI component (stateful, session-aware)
│   └── next.config.ts         # Static export configuration
│
├── terraform/                 # Infrastructure as Code
│   ├── main.tf                # All AWS resources
│   ├── variables.tf           # Input variable definitions
│   ├── outputs.tf             # Exported URLs and resource names
│   └── versions.tf            # Provider version constraints
│
├── scripts/
│   ├── deploy.ps1             # Windows full-deploy script
│   ├── deploy.sh              # Linux/macOS full-deploy script
│   ├── destroy.ps1            # Windows teardown script
│   └── destroy.sh             # Linux/macOS teardown script
│
└── .env                       # Local environment configuration
```

---

## ⚠️ Destroy Guide (Read This)

> **This section is especially important if you are learning AWS.** Cloud resources cost real money even when idle — particularly CloudFront distributions and S3 buckets. Always destroy your infrastructure when you are done experimenting.

### Why You Must Destroy

When you run `terraform apply`, AWS starts billing you for:

| Resource | Cost Risk |
|---|---|
| **CloudFront** | Small monthly minimum even with zero traffic |
| **Lambda** | Free tier is generous, but watch in production |
| **S3** | Minimal per-GB, but buckets must be *emptied* before Terraform can delete them |
| **API Gateway** | Charged per request; low idle cost, but adds up |

The destroy scripts handle the trickiest part: **S3 buckets must be emptied before Terraform can delete them.** If you try to run `terraform destroy` on a non-empty bucket, it will error out and leave partial resources running.

### How to Destroy

**Windows (PowerShell):**
```powershell
.\scripts\destroy.ps1 -Environment dev -ProjectName twin
```

**Linux / macOS (Bash):**
```bash
bash scripts/destroy.sh dev twin
```

**What the destroy script does, in order:**
1. Selects the correct Terraform workspace (`dev`, `test`, or `prod`)
2. Empties the **frontend S3 bucket** — removes all HTML/CSS/JS files
3. Empties the **memory S3 bucket** — removes all conversation history
4. Runs `terraform destroy` to delete all remaining AWS resources
5. Prints instructions to clean up the Terraform workspace

### After Destroy — Clean Up the Workspace

The destroy script will print these commands. Run them to fully clean up:

```bash
cd terraform
terraform workspace select default
terraform workspace delete dev
```

### Manual Destroy (If the Script Fails)

If the script errors out, you can do it step by step:

```bash
# 1. Empty the S3 buckets first (get names from: terraform output)
aws s3 rm s3://twin-dev-frontend-<your-account-id> --recursive
aws s3 rm s3://twin-dev-memory-<your-account-id> --recursive

# 2. Navigate to terraform directory
cd terraform

# 3. Select the right workspace
terraform workspace select dev

# 4. Destroy all infrastructure
terraform destroy \
  -var="project_name=twin" \
  -var="environment=dev"

# 5. Type 'yes' when prompted
```

### Verify Destruction

After destroying, confirm in the AWS Console that these are gone:

- **Lambda** → `twin-dev-api` should not exist
- **API Gateway** → no `twin-dev` API
- **S3** → no `twin-dev-*` buckets
- **CloudFront** → distribution deleted (takes ~5 minutes to fully deactivate)

> **Learner tip:** Set up [AWS Budgets](https://aws.amazon.com/aws-cost-management/aws-budgets/) with an alert at $5/month. You will get an email the moment any resource starts accumulating unexpected charges — a great safety net while you are still learning.

---

## License

Apache 2.0 — see [LICENSE](LICENSE).

---

*Built by [Raktima Barman](https://www.linkedin.com/in/raktimabarman96/) as part of a hands-on AWS self-study journey.*
