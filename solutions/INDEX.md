# Solutions vérifiées du fil rouge

Les solutions du projet fil rouge (`Snowflake-terraform/project`) ont été synchronisées dans `solutions/fil-rouge/`.

> **Avertissement** : les fichiers contenant des secrets (`*.tfvars` non `.example` et `backend.hcl`) ont été retirés automatiquement. Utilisez uniquement les `.example` pour créer vos propres fichiers sensibles.

## Correspondance modules ↔ dossiers solutions

| Module | Dossier solution | Description |
|---|---|---|
| M00 — Setup | (pas de code) | Utiliser `scripts/Learner-Login.ps1` et `scripts/New-SnowflakeConnection.ps1` |
| M01 — IaC Workflow | `solutions/fil-rouge/01-day1-basics` | Premier déploiement : database, schema, warehouse |
| M02 — State Management | `solutions/fil-rouge/02-day1-state` | Backend Azure Blob Storage |
| M03 — Import Brownfield | `solutions/fil-rouge/03-day2-modules` | Import/`moved` (reprendre les patterns de `landing-zone`/`rbac`) |
| M04 — Variables & Outputs | `solutions/fil-rouge/01-day1-basics` | Variables validées, outputs, lifecycle |
| M05 — Modules | `solutions/fil-rouge/03-day2-modules/modules/landing-zone` | Module landing-zone |
| M06 — Dynamic Logic | `solutions/fil-rouge/03-day2-modules/environments/dev` | `for_each`, `count`, dynamic blocks |
| M07 — CI/CD Pipeline | `solutions/fil-rouge/03-devops-setup` | Azure DevOps variable groups |
| M08 — Environments | `solutions/fil-rouge/03-day2-modules/environments` | Dev/Test/Prod + `05-capstone/environments` |
| M09 — Snowflake Advanced | `solutions/fil-rouge/01-snowflake-learners`, `solutions/fil-rouge/05-capstone` | Users, grants, objets avancés |
| M10 — Security & Auth | `solutions/fil-rouge/03-day2-modules/modules/key-vault-rsa` | Key Vault + JWT RSA |
| M11 — RBAC | `solutions/fil-rouge/04-day3-rbac/environments/dev` | Rôles et grants |
| M12 — Capstone | `solutions/fil-rouge/05-capstone/environments/dev` | Plateforme complète |
| M13 — FinOps | `solutions/fil-rouge/06-data-products` | Cost / tags / resource monitors |
| M14 — Data Products | `solutions/fil-rouge/06-data-products` | Data products SALES/FINANCE |

## Mise à jour

Pour resynchroniser après une nouvelle rotation de PAT ou des corrections :

```powershell
robocopy "D:\Data2AI Academy\Snowflake-terraform\project" "solutions\fil-rouge" /MIR /XD .terraform secrets /XF *.log *.tfplan *.tfstate*
```

Puis supprimer les fichiers sensibles (seuls les `.example` doivent rester) :

```powershell
Get-ChildItem -Recurse -Path 'solutions\fil-rouge' -File | Where-Object { ($_.Extension -eq '.tfvars' -and $_.Name -notlike '*.example') -or $_.Name -eq 'backend.hcl' } | Remove-Item -Force
```
