# Template de module

Copiez ce dossier pour creer un nouveau module respectant l'architecture.

## Convention d'arborescence

```text
mon-module/
├── versions.tf
├── variables.tf
├── main.tf
└── outputs.tf
```

## Regles immuables

1. `versions.tf` est identique a tous les modules (Terraform 1.14.5, Snowflake 2.14.0).
2. `main.tf` declare `locals` pour le `suffix` (`dev` vs `uat`) et le tag `owner`.
3. Aucun `provider`, aucun `backend` dans un module.
4. `variables.tf` + `outputs.tf` forment le contrat.
5. Les ressources portent le nom local `this` quand il n'y en a qu'une principale.
