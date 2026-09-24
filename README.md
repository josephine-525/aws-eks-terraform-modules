# terraform-modules

Shared, reusable, **versioned** Terraform modules for the EKS platform. Same philosophy as [`helm-charts`](https://github.com/josephine-525/aws-eks-helm-charts) and [`ci-templates`](https://github.com/josephine-525/aws-eks-ci-templates): the platform owns the module code, consumers pin an exact git tag, and nothing changes under a consumer's feet just because this repo gets a new commit. See [`aws-eks-gitops-platform`](https://github.com/josephine-525/aws-eks-gitops-platform) for the full 8-repo picture.

[`aws-eks-infra`](https://github.com/josephine-525/aws-eks-infra) is the only consumer today, pulling each module via `source = "git::https://.../terraform-modules.git//<module>?ref=vX.Y.Z"`.

## Modules

| Module | What it provisions |
|---|---|
| `vpc/` | VPC, public/private subnets across multiple AZs, routing, NAT, a free DynamoDB Gateway VPC endpoint |
| `db/` | The DynamoDB table the app reads/writes |
| `security/` | IAM whose trust policy does **not** depend on a compute resource that doesn't exist yet — the EKS cluster/node IAM roles, standalone DynamoDB/LBC permission-policy documents. (Deliberately *not* the IRSA roles — see "A real design boundary" below.) |
| `compute/` | The EKS cluster, node groups, IRSA roles, VPC CNI/CloudWatch Observability addons, security groups, ALB security group |
| `ecr/` | Container image repositories (one shared registry per the whole account, not per environment) |
| `budget-alert/` | SNS topic + AWS Budget for monthly spend alerts |
| `guardduty/`, `config/` | Account-level security baseline (threat detection, configuration compliance) |

## A real design boundary, not an arbitrary split

`security/` and `compute/` look like they could merge, but can't, for a concrete reason: an **IRSA** role's trust policy is federated to the EKS cluster's own OIDC provider ARN — which only exists *after* the cluster does. So `security/` holds the IAM that's independent of any specific resource (the cluster role, the node role, standalone permission-policy documents), while every IRSA role (the app's own DynamoDB access, the AWS Load Balancer Controller's role, CloudWatch Observability's role) has to live in `compute/`, permanently, because its trust policy can't be written until the cluster exists. Real takeaway: a security/compute split can own *what's allowed* independently of compute, but never *who's trusted* once that trust is federated to a resource compute itself creates.

## Versioning — lockstep tags, and why that's a scale tradeoff

One repo-wide semver git tag covers every module in it (plain `git tag`, no automation). A consumer pinned to `v1.0.0` for `compute` is never forced onto `v1.1.0` just because it exists — `v1.1.0` added `guardduty`/`config` with zero changes to `vpc`/`db`/`security`/`compute`, and every existing consumer of those stayed on `v1.0.0` without needing to care. This works because there's realistically one team touching a handful of modules; at real company scale (many modules, many teams, very different change velocity per module) lockstep tagging breaks down — the fix at that scale is per-module prefixed tags or splitting each module into its own repo, trading "one clone gets you everything" for unambiguous per-module version history. Not warranted here yet; flagged as a deliberate choice.

**Real version history, not a hypothetical changelog:**

| Tag | What changed | Why |
|---|---|---|
| `v1.0.0` | Initial extraction of `vpc`/`db`/`security`/`compute`/`ecr`/`budget-alert` from a single-project Terraform layout | Start of the multi-repo, layered architecture |
| `v1.1.0` | Added `guardduty`/`config` | Account-level security baseline, zero changes to existing modules |
| `v2.0.0` | **Breaking**: `eks_expense_backend_sa_namespace`/`eks_expense_backend_sa_name` became required (no default) inputs to `compute` | The IRSA trust policy had `system:serviceaccount:expense:expense-backend` hardcoded from a retired naming scheme — silently wrong once the real ServiceAccount became `team-payments/team-payments-backend-common-web-service`, breaking `AssumeRoleWithWebIdentity`. Fixed by requiring the caller to pass the real values instead of a module-side default. |
| `v2.1.0` | Added a free DynamoDB Gateway VPC endpoint to `vpc` | Cost/networking cleanup, no interface change |
| `v2.1.1` | Reverted a `vpc` change (`data.aws_region.current.name` — the `region` attribute isn't available on that data source in the pinned provider version) | Provider compatibility fix |
| `v2.2.0` | `compute` adopts VPC CNI as a managed `aws_eks_addon`, `enableNetworkPolicy = "true"` | Found live: this EKS cluster's VPC CNI shipped with `NetworkPolicy` enforcement **off by default** — every `NetworkPolicy` in the platform's GitOps layer was applying cleanly and enforcing nothing. See `aws-eks-infra`'s troubleshooting log for the full story. |

## Local development

Each module has its own `.terraform`/state cache when run standalone (`terraform init` inside a module directory) — this repo has no shared root module and isn't meant to be `apply`'d directly; it's a library, consumed by `aws-eks-infra`.
