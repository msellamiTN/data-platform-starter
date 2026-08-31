# Convention de nommage

## Règle générale

```text
<PREFIXE_APPRENANT>_<ZONE>_<ENVIRONNEMENT>
```

## Préfixe apprenant

- 3 à 5 caractères alphanumériques en majuscules;
- attribué par le formateur en début de session;
- unique parmi tous les participants;
- exemple : `ABC`, `XYZ`, `MSE`.

## Zone

| Zone | Rôle | Couches |
|---|---|---|
| `RAW` | Ingestion brute | Bronze |
| `ETL` | Transformation | Silver |
| `CURATED` | Agrégation métier | Gold |
| `FINOPS` | Observabilité et coûts | Monitoring |
| `SEC` | Sécurité et gouvernance | RBAC, tags, policies |

## Environnement

| Suffixe | Rôle |
|---|---|
| `DEV` | Développement |
| `UAT` | Validation |
| `PROD` | Production |

## Exemples

| Ressource | Nom |
|---|---|
| Database | `ABC_RAW_DEV` |
| Schema | `ABC_ETL_UAT.SILVER` |
| Warehouse | `WH_ABC_CURATED_PROD` |
| Resource monitor | `RM_ABC_DEV` |
| Storage integration | `SI_ABC_RAW_DEV` |
| Azure storage account | `stabcuratedabcdev` |

## Cas particulier des warehouses

Les warehouses portent le préfixe `WH_` pour les distinguer des bases :

```text
WH_<PREFIXE>_<ZONE>_<ENVIRONNEMENT>
```

## Cas particulier des resource monitors

```text
RM_<PREFIXE>_<ENVIRONNEMENT>
```

Les resource monitors ne portent pas de zone car ils s'appliquent au compte ou à un warehouse.

## Règles de casse

| Type | Casse | Exemple |
|---|---|---|
| Snowflake databases, schemas, warehouses | UPPER_SNAKE | `ABC_RAW_DEV` |
| Snowflake roles | UPPER_SNAKE | `ROLE_ABC_DEV` |
| Snowflake users | UPPER_SNAKE | `USER_ABC_SVC` |
| Azure resources | lower | `stabcuratedabcdev` |
| Terraform resources | snake_case | `snowflake_database.raw_dev` |
| Terraform variables | snake_case | `learner_prefix` |
| Terraform locals | snake_case | `database_name` |
