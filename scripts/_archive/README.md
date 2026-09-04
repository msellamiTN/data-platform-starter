# scripts/_archive/

This directory contains deprecated, instructor-only, or superseded scripts
that are no longer part of the learner workflow.

## Why archived?

| Script | Reason |
|---|---|
| `Add-LearnerServicePrincipals.ps1/.sh` | Superseded by Terraform `02-azuread-learners` |
| `Add-LearnerUsers.ps1/.sh` | Superseded by Terraform `02-azuread-learners` |
| `Add-SnowflakeLearners.ps1/.sh` | Superseded by Terraform `01-snowflake-learners` |
| `Set-SnowflakePATs.ps1` | Deprecated — shared PAT model (see `instructor-setup.md`) |
| `New-SnowflakePATs.ps1` | Deprecated — shared PAT model |
| `Clean-LabResources.ps1` | Superseded by `Reset-Lab.ps1` |
| `Configure-TerraformProvider.ps1` | Not used in current curriculum |
| `Install-LabEnvironment.ps1` | Superseded by `Install-Tools.ps1` + Terraform modules |
| `Setup-Day0.ps1/.sh` | Superseded by `Install-Tools.ps1` + `Learner-Login.ps1` |
| `StudentLabRunner.ps1` | Superseded by `SelfPacedLab.ps1` |
| `Test-LabEnvironment.ps1` | Superseded by `Test-LabConnectivity.ps1` |
| `setup_tools.md` | Legacy documentation, superseded by course materials |
| `.env-entreprise` | Legacy config file |

## Usage

These scripts are kept for reference only. Do not use them in the training.
The current learner workflow uses the scripts in `scripts/` (parent directory).
