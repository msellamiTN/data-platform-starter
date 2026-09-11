# Best Practices — Data Platform as Code GlobalBank

## 1. Versioning

- Pinner `required_version = "= 1.14.5"`.
- Pinner `snowflakedb/snowflake = "= 2.14.0"`.
- Memes versions dans `envs/` et dans chaque `modules/*/versions.tf`.
- Jamais de `~>`, `>=` ou `latest` en formation.

## 2. Structure d'un module

Un module = un dossier avec exactement 4 fichiers :

```text
mon-module/
├── versions.tf
├── variables.tf
├── main.tf
└── outputs.tf
```

- Pas de `provider.tf` dans un module.
- Pas de `backend.tf` dans un module.
- Pas de `terraform.tfvars` dans un module.

## 3. Conventions de nommage

- Ressource principale unique : `resource "snowflake_xxx" "this"`.
- Collections : `for_each` sur un `map(object({...}))`.
- Nommage des objets Snowflake : `GB_<domaine>_<ressource>_<ENV>`.
- Exemple : `GB_CUSTOMER_DB`, `GB_CUSTOMER_DB_UAT`.

## 4. Gestion des environnements

```hcl
locals {
  suffix = var.environment == "dev" ? "" : "_${upper(var.environment)}"
}
```

- `dev` garde le nom court, `uat`/`prod` ajoutent le suffixe.
- Cela garantit `terraform plan` vide apres un `moved` correct.

## 5. Contrat d'interface

- `variables.tf` = ce que le module attend.
- `outputs.tf` = ce que le module promet.
- Les `outputs` ne doivent jamais contenir de secrets.
- Exporter des IDs, des noms et des maps de contrats.

## 6. Separation des responsabilites

| Type | But | Exemples |
|---|---|---|
| Bootstraps | Ressources techniques partagees | `rbac`, `compute` |
| Spokes | Data Products metier | `landing-zone`, `data-domain`, `data-mart` |

- Les bootstraps s'appliquent en phase 1.
- Les spokes consomment les `outputs` des bootstraps en phase 2.

## 7. State et CI/CD

- Un state par combinaison `(learner, env)` : `APP01/dev.tfstate`.
- Azure AD auth obligatoire pour le backend : `use_azuread_auth = true`.
- Pipeline : `terraform plan -out=tfplan -input=false`, puis `terraform apply tfplan -input=false`.
- Jamais `-auto-approve` en production.

## 8. Deplacements et imports

- Utiliser `moved {}` avant de renommer une ressource.
- Utiliser `terraform import` pour adopter un objet existant.
- Valider avec `terraform plan` a zero changement apres chaque refonte.
