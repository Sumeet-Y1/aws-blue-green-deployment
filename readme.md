# 🔵🟢 AWS Blue-Green Deployment

> Zero-downtime deployment pipeline that automatically alternates between Blue and Green environments on every git push  with instant rollback capability.

---

## 🏗️ Architecture

```
                        ┌─────────────────────────────────────────┐
                        │              GitHub Actions              │
                        │  push → detect active → deploy inactive  │
                        │     → health check → flip ALB           │
                        └──────────────────┬──────────────────────┘
                                           │
                                    ┌──────▼──────┐
                                    │  AWS ECR    │
                                    │ :blue :green│
                                    └──────┬──────┘
                                           │
          ┌──────────────────────────────── ▼ ────────────────────────────────┐
          │                     AWS VPC (ap-south-1)                          │
          │                                                                    │
          │          ┌─────────────────────────────────────┐                  │
          │          │    Application Load Balancer (ALB)   │ ← HTTP :80      │
          │          └──────────┬──────────────┬───────────┘                  │
          │                     │              │                               │
          │          ┌──────────▼──┐      ┌────▼────────┐                     │
          │          │ 🔵 Blue EC2  │      │ 🟢 Green EC2 │                    │
          │          │   :8080     │      │   :8080     │                     │
          │          │  ap-south-1a│      │  ap-south-1b│                     │
          │          └─────────────┘      └─────────────┘                     │
          │                                                                    │
          │   ALB points to ONE environment at a time                         │
          │   Other environment stays idle as instant rollback                │
          └────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Tech Stack

| Layer | Technology |
|---|---|
| **Application** | Spring Boot 3.5, Java 21 |
| **Containerization** | Docker, AWS ECR |
| **Infrastructure** | Terraform |
| **Compute** | AWS EC2 (t3.micro) |
| **Load Balancing** | AWS Application Load Balancer |
| **CI/CD** | GitHub Actions |
| **OS** | Ubuntu 22.04 LTS |

---

## 🔵🟢 How Blue-Green Works

```
Initial State:
🔵 Blue (v6) → LIVE   ← ALB routes here
🟢 Green (v5) → IDLE  ← standby for rollback

git push v7 triggers pipeline:
1. Pipeline detects Blue is LIVE
2. Builds v7 image → pushes to ECR as :green
3. Deploys v7 to Green EC2
4. Health checks Green directly on port 8080
5. All healthy? → ALB flips to Green
6. Zero downtime users never notice

After deployment:
🔵 Blue (v6) → IDLE   ← instant rollback available
🟢 Green (v7) → LIVE  ← ALB routes here

Next push alternates back to Blue. And so on.
```

---

## ⚡ Key Features

### 🔄 Automatic Environment Detection
Pipeline checks which environment ALB is currently pointing to, then deploys to the other one automatically no manual configuration needed.

### 🏥 Health Checks Before Flip
Before switching traffic, pipeline directly hits the inactive EC2 on port 8080 and retries 10 times (every 15 seconds). ALB only flips if health check passes.

### ↩️ Instant Rollback
Previous version always stays running on the idle environment. Rollback is a single AWS CLI command takes 5 seconds, not 5 minutes.

### 🚫 Zero Downtime
ALB switches target groups atomically. Users experience no interruption during deployments.

---

## 📁 Project Structure

```
aws-blue-green-deployment/
├── src/
│   └── main/java/com/devops/aws_blue_green_deployment/
│       ├── AwsBlueGreenDeploymentApplication.java
│       └── AppController.java
├── terraform/
│   └── main.tf          # VPC, ALB, Blue/Green EC2s, Target Groups
├── .github/
│   └── workflows/
│       └── deploy.yml   # Blue-Green CI/CD pipeline
└── Dockerfile
```

---

## 🛠️ Infrastructure (Terraform)

```bash
cd terraform
terraform init
terraform apply    # provisions everything
terraform destroy  # tears down everything
```

**Resources provisioned (21 total):**
- VPC + 2 Public Subnets (ap-south-1a, ap-south-1b)
- Internet Gateway + Route Tables
- Security Groups (ALB + EC2)
- Application Load Balancer
- **Blue Target Group** + **Green Target Group**
- ALB Listener (points to Blue by default)
- Blue EC2 Instance (t3.micro, Ubuntu 22.04, 20GB)
- Green EC2 Instance (t3.micro, Ubuntu 22.04, 20GB)
- ECR Repository (`:blue` and `:green` tags)
- IAM Role + Instance Profile (ECR + SSM access)

---

## 🔌 API Endpoints

| Endpoint | Description |
|---|---|
| `GET /api/hello` | Returns server hostname + timestamp |
| `GET /api/version` | Returns current version + environment |
| `GET /actuator/health` | Health check endpoint |

### Sample Response `/api/version`
```json
{
  "version": "v7",
  "environment": "blue"
}
```
> `environment` changes between `blue` and `green` on every deployment proof the ALB is alternating environments.

---

## 🚀 CI/CD Pipeline Flow

```
git push origin main
       │
       ▼
GitHub Actions
       │
       ├── Build JAR (Maven)
       ├── Build Docker image
       ├── Push to ECR (:blue or :green)
       ├── Detect active environment (Blue or Green)
       ├── Deploy to INACTIVE environment via SSM
       ├── Health check inactive (10 retries x 15s)
       ├── ALB flip to inactive environment
       └── Verify deployment → rollback if failed
```

---

## ↩️ Manual Rollback

If anything goes wrong after deployment, rollback in one command:

```bash
# Rollback to Blue
aws elbv2 modify-listener \
  --listener-arn YOUR_LISTENER_ARN \
  --default-actions Type=forward,TargetGroupArn=YOUR_BLUE_TG_ARN \
  --region ap-south-1

# Rollback to Green
aws elbv2 modify-listener \
  --listener-arn YOUR_LISTENER_ARN \
  --default-actions Type=forward,TargetGroupArn=YOUR_GREEN_TG_ARN \
  --region ap-south-1
```

**5 seconds. No redeployment. Previous version instantly live.**

---

## ⚙️ Setup & Deployment

### Prerequisites
- AWS CLI configured
- Terraform installed
- Docker installed
- Java 21

### GitHub Secrets Required
| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS credentials |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials |
| `BLUE_INSTANCE_ID` | Blue EC2 instance ID |
| `GREEN_INSTANCE_ID` | Green EC2 instance ID |
| `BLUE_TG_ARN` | Blue target group ARN |
| `GREEN_TG_ARN` | Green target group ARN |
| `ALB_LISTENER_ARN` | ALB listener ARN |
| `ALB_DNS` | ALB DNS name |

### Deploy
```bash
# 1. Clone
git clone https://github.com/Sumeet-Y1/aws-blue-green-deployment

# 2. Provision infrastructure
cd terraform && terraform apply

# 3. Push Docker images to ECR
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com
docker build -t aws-blue-green-deployment .
docker tag aws-blue-green-deployment:latest ECR_URL:blue
docker tag aws-blue-green-deployment:latest ECR_URL:green
docker push ECR_URL:blue
docker push ECR_URL:green

# 4. Add GitHub secrets
# 5. Push code → pipeline auto-deploys!
```

### Destroy
```bash
aws ecr delete-repository --repository-name aws-blue-green-deployment --force --region ap-south-1
cd terraform && terraform destroy
```

---

## 👤 Author

**Sumeet** - [GitHub](https://github.com/Sumeet-Y1)