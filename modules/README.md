# Modules réutilisables

Ce dossier contient les modules Terraform créés par l'apprenant au fil du parcours.

## Convention

- un module par responsabilité métier;
- un module ne dépend pas d'un environnement spécifique;
- les noms de ressources utilisent des variables, pas de valeurs en dur;
- chaque module expose des `variables.tf`, `outputs.tf` et un `README.md`;
- aucun module ne contient de secret ou de credential.

## Modules créés pendant la formation

| Module | Jour | Description |
|---|---|---|
| `landing-zone` | Jour 3 | Base de données, schémas et warehouse de base |
| `rbac` | Jour 4 | Rôles, privilèges et grants |
| `ingestion` | Jour 4 | Storage integration et stages vers ADLS |
| `finops` | Jour 5 | Resource monitors et tags de coût |

L'apprenant crée chaque module en suivant les ateliers correspondants.
