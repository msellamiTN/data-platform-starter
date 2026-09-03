# AGENTS.md

## Repository purpose

This repository is a starter for a Data Platform as Code lab using Terraform, Snowflake, Azure and Azure DevOps. The project is intentionally scaffolded for learners: it provides governance, validation scripts, environment structure and documentation, but it does not include concrete resource definitions or Terraform state.

Use the project docs as the source of truth:
- [README.md](README.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/naming-conventions.md](docs/naming-conventions.md)
- [docs/runbook.md](docs/runbook.md)

## What this repo contains

- `environments/dev`, `environments/uat`, `environments/prod`: environment roots for Terraform work
- `modules/`: reusable Terraform modules to create as part of the course
- `scripts/`: local install and validation helpers for Windows and Linux/macOS
- `azure-pipelines.yml`: CI/CD pipeline definition for validation, plan, approval, apply and drift audit
- `docs/`: architecture, naming and operational guidance

This repo is not a finished Terraform deployment. Learners add `.tf` files and module code themselves as they progress through the labs.

## Project conventions

- Naming convention for resources: `<LEARNER_PREFIX>_<ZONE>_<ENVIRONMENT>`.
- Keep environment-specific code under `environments/<env>/` and reusable logic under `modules/`.
- Follow the repo's Azure DevOps workflow and avoid introducing ad hoc deployment patterns.
- Do not commit secrets, PATs, private keys, `.tfvars`, `.env`, `backend.hcl`, state files or generated Terraform artifacts.
- Treat the state as remote-only and managed through Azure Blob Storage; never check in local state.

## Validation commands

Preferred validation flow for local work:

- Linux/macOS: `./scripts/validate.sh`
- Windows: `powershell -ExecutionPolicy Bypass -File .\scripts\validate.ps1`

Common checks when working under an environment directory:

```bash
terraform fmt -recursive -check
terraform init -backend=false
terraform validate
```

When operating in Azure DevOps, keep the pipeline behavior aligned with [azure-pipelines.yml](azure-pipelines.yml) and avoid hard-coded credentials.

## Safety rules

- Never add secrets to source control.
- Never suggest publishing a Terraform plan or applying infrastructure without review.
- Do not create destructive commands such as `terraform destroy` unless the user explicitly requests them and has confirmed the environment target.
- Prefer the existing repository patterns and docs over making assumptions about project structure.

## Working style for agents

- Prefer minimal, targeted changes.
- Link to existing docs instead of duplicating their content.
- If new files are needed, keep them consistent with the learning structure and naming conventions.
- Preserve the fact that this project is a training starter rather than a production-ready deployment template.
