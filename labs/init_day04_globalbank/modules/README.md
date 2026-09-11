# Taxonomie des modules GlobalBank

Le decoupage evite qu'une equipe "Metier" ecrase ou attende l'autre :

## 1. Bootstraps techniques (Team Platform)

Ces modules n'ont aucune donnee metier. Ils fournissent les briques partagees sans lesquelles les spokes ne peuvent pas etre securises.

| Module | Role | Ressources principales |
|---|---|---|
| `rbac` | Identite & permissions | `snowflake_account_role` + grants |
| `compute` | Ressources de calcul | `snowflake_warehouse` avec politique FinOps |

Contraintes d'orchestration :
- S'appliquent en premier (`terraform apply` phase 1).
- Aucune dependance envers un spoke.
- Exposent `role_names` et `warehouse_names` en `outputs`.

## 2. Spokes metier (Data Engineering, Business Data, BI)

Ces modules representent des Data Products. Chacun possede sa propre database, son schema et ses tables.

| Module | Equipe | Ressources principales |
|---|---|---|
| `landing-zone` | Data Engineering | Database RAW / CORE + schema LANDING / DIM |
| `data-domain` | Business Data | Database CUSTOMER / PRODUCT / CAMPAIGN + schema BUSINESS |
| `data-mart` | BI / Analytics | Database CUSTOMER / FINANCE / TRANSACTION MART + schema MART |

Contraintes d'orchestration :
- S'appliquent en phase 2.
- Consomment les outputs du bootstrap (roles, warehouses).
- Exposent des contrats (`domain_contract`, `mart_contract`) pour les grants J5.

## Notes de realisation

- Chaque module doit respecter le squelette suivant : `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`.
- Le nom de la ressource principale doit etre `this`.
- Le suffixe d'environnement est calcule avec `var.environment == "dev" ? "" : "_${upper(var.environment)}"`.
- Aucune chaine en dur ; tout ce qui varie passe par `variables.tf`.
- Aucun `provider` ni `backend` dans un module : ils restent dans `envs/`.

## Template

Le dossier `_template/` contient un module vierge respectant cette architecture. Pour creer un nouveau module :

```bash
cd courses/initiation/day-04/terraform/modules
cp -r _template mon-nouveau-module
```
