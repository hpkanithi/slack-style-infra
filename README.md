# Slack-style job queue (Architecture Breakdown series, Company 1)

Infrastructure inspired by publicly documented patterns from Slack's engineering blog. This is not Slack's actual production architecture, and it isn't claimed to be. It's a small, reproducible build of the pattern behind Slack's job queue, with the substitutions explained below.

Full writeup with the Slack context and what broke while building it: `[BLOG POST LINK]`

## What this is

Slack's 2016 job queue outage is the starting point: a database slowdown caused workers to fall behind, Redis filled its memory, and the queue deadlocked because dequeuing a job also required a small memory allocation. The fix Slack shipped in 2017 put a durable buffer (Kafka) in front of Redis so a backlog lands on disk instead of filling RAM.

This repo builds that same shape at a scale that fits on a personal AWS account: a web service enqueues messages, a durable buffer holds them, and a worker service processes them. Killing the worker doesn't lose messages, it just delays them. That's the whole lesson, and it's demonstrable end to end.

## Architecture

```
                        +------------------------------------------------+
                        | VPC 10.0.0.0/16  ·  us-east-2  ·  2 AZs         |
                        |                                                  |
  Internet --> ALB -----+--> [public subnets]                             |
               (HTTP)   |                                                  |
                        |  [private subnets]                              |
                        |   +--------------+    enqueue    +-----+        |
                        |   | ECS: web svc |-------------->| SQS |        |
                        |   | (2 tasks)    |               +--+--+        |
                        |   +--------------+                  | poll      |
                        |   +--------------+                  |           |
                        |   | ECS: worker  |<-----------------+           |
                        |   | (1 task)     |--> ElastiCache Redis         |
                        |   +--------------+     (results/cache)          |
                        |                                                  |
                        |   EC2 ASG (t4g.micro x3) = ECS capacity         |
                        |   1x NAT GW (single AZ, cost decision)          |
                        +------------------------------------------------+
                              SQS DLQ <-- failed messages (maxReceiveCount 3)
                              CloudWatch alarm on DLQ depth > 0
```

`POST /message` hits the ALB, the web service enqueues to SQS and returns immediately. The worker polls SQS, does a couple seconds of fake processing (standing in for a link unfurl), and writes the result to Redis. `GET /messages` reads it back.

## What's built vs. what Slack actually runs

| Slack production | This build | Why the substitution |
|---|---|---|
| EC2 fleet running the webapp (~60,000 instances) | ECS on EC2, 3x `t4g.micro` | Same compute shape at a fraction of the scale; teaches capacity providers and ASGs |
| Kafka + Kafkagate (durable buffer) | SQS with a dead-letter queue | Managed durable buffer, same role: absorb enqueue spikes on disk |
| Redis job queue / caches | ElastiCache Redis | Workers write results here |
| JQRelay + workers | ECS worker service polling SQS | Same consumer role |
| Whitecastle (multi-VPC, Transit Gateway) | One VPC, 2 AZs, public/private subnets | Multi-VPC/TGW is overkill at this scale |
| Vitess (sharded MySQL) | Not built | Persistence wasn't this build's focus |
| Cell-based AZ isolation | Not built, discussed in the blog post | Real engineering, just not this build's scope |

## Deliberate tradeoffs

**SQS instead of self-hosting Kafka.** Running Kafka for a workload this small is picking a tool because it's impressive, not because the job needs it. Kafka shows up in a later company in this series where the scale actually justifies it.

**ECS on EC2, not Fargate.** The harder path on purpose: a launch template, an ASG, and a capacity provider instead of letting AWS manage compute. Fargate is the right call if you just want it running.

**One NAT gateway, not one per AZ.** A real cost/availability tradeoff, not a shortcut. A second NAT gateway runs about $32/month; production would run one per AZ so a single zone failure doesn't take out egress for everyone.

**DLQ and CloudWatch alarm from day one.** A poison message is usually the first thing that breaks a queue consumer in production. `maxReceiveCount = 3` before a message reaches the DLQ, with an alarm on DLQ depth so it doesn't sit there unnoticed.

**Task IAM roles scoped per service.** The web task's role can only call `sqs:SendMessage`. The worker's role can only receive and delete. Neither can touch the other side of the queue.

## Cost

Approximate hourly burn with everything running, us-east-2:

| Resource | ~$/hr |
|---|---|
| 3x t4g.micro (ECS hosts) | 0.025 |
| ALB | 0.023 + LCU (negligible here) |
| ElastiCache cache.t4g.micro | 0.016 |
| NAT gateway | 0.045 + data |
| SQS / ECR / CloudWatch | ~free at this volume |
| **Total** | **~$0.11-0.13/hr** |

Rules followed while building: `terraform destroy` at the end of every session, never leave the NAT gateway up overnight, and a $10 billing alarm was the first thing deployed, before any other infrastructure.

## Deploy

Requires Docker Desktop, the AWS CLI configured, and Terraform.

```powershell
cd terraform
terraform apply
```

Brings up all 53 resources in about 4 minutes (Redis and the ALB are the slow parts). `terraform destroy` runs in roughly the same range, longer if a stale state lock needs clearing first (see Known issues below). Then build and push the app images, since ECR starts empty on every fresh apply:

```powershell
$ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.us-east-2.amazonaws.com"

docker buildx build --platform linux/arm64 -t "$ACCOUNT_ID.dkr.ecr.us-east-2.amazonaws.com/ecr-repository-web:latest" --push ./app/web
docker buildx build --platform linux/arm64 -t "$ACCOUNT_ID.dkr.ecr.us-east-2.amazonaws.com/ecr-repository-worker:latest" --push ./app/worker
```

The `--platform linux/arm64` flag matters: the ASG runs Graviton (`t4g.micro`) instances, and a plain `docker build` on an amd64 host silently builds the wrong architecture. `docker buildx build --push` forces the correct cross-platform path.

## Demo

Kill the worker, prove nothing gets lost:

```powershell
aws ecs update-service --cluster slack-style-cluster --service slack-style-worker-svc --desired-count 0
# post messages, watch SQS depth climb
aws ecs update-service --cluster slack-style-cluster --service slack-style-worker-svc --desired-count 1
# watch it drain back to zero, confirm all messages processed
```

Trigger the DLQ path:

```powershell
Invoke-RestMethod -Uri "http://$ALB/message" -Method Post -ContentType "application/json" -Body (@{ text = "poison" } | ConvertTo-Json)
# 3 retries, ~60s apart, then it lands in the DLQ and the CloudWatch alarm fires
```

## Teardown

```powershell
terraform destroy
```

The Terraform state bucket has `prevent_destroy` set, since it holds this project's own remote state. If a destroy needs to include it for some reason, that requires a deliberate `terraform state rm` first, then `terraform import` back before the next apply. Day to day, `terraform destroy` just leaves the bucket alone and tears down everything else.

## Known issues hit while building this

**ARM64 image mismatch.** ECS runs Graviton instances; a plain `docker build` on an amd64 machine builds the wrong architecture without erring. Fixed by building through a proper `docker buildx` multi-platform builder.

**ECS deployment capacity (`RESOURCE:ENI`).** With exactly 3 instances for exactly 3 desired tasks, a rolling deployment has no spare capacity to start a new task before killing the old one, so every deploy failed to place tasks. Fixed with `deployment_maximum_percent = 100`, `deployment_minimum_healthy_percent = 0`, and `availability_zone_rebalancing = "DISABLED"` on both ECS services, so deployments replace tasks one for one.

**PowerShell + AWS CLI JSON quoting.** Passing a JSON string through a PowerShell variable to `aws` strips quotes on Windows. Shorthand CLI syntax (`imageDigest=sha256:...`) avoids the problem entirely.

**ECR repos need `force_delete = true`.** Without it, `terraform destroy` fails on "repository not empty" and requires manually clearing images first.

**Stale S3 state lock.** If a previous `apply` or `destroy` doesn't exit cleanly, the native S3 lock can linger and block the next command with `Error acquiring the state lock`. Fixed with `terraform force-unlock <lock-id>` from the error message.

## Repo structure

```
Slack-Style/
  terraform/     Infrastructure as code
  app/
    web/         Flask service, enqueues to SQS
    worker/      Polls SQS, writes results to Redis
```
