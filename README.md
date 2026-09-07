# data-platform-starter

Squelette de gouvernance pour un projet Data Platform as Code avec Terraform, Snowflake et Azure DevOps.

## Objectif

Ce dépôt est le **point d'entrée unique** de l'apprenant. Il contient :

- les **scripts d'installation et de configuration** pour préparer le poste;
- la **structure de gouvernance** (dossiers, qualité, CI/CD, docs);
- les **scripts de validation** locale.

L'apprenant clone ce dépôt au Jour 0, installe les outils, configure sa connexion Snowflake, puis crée ses fichiers `.tf` au fil des modules. **Aucun fichier `.tf` de ressource n'est fourni** : l'apprenant les crée lui-même.

## Workflow de l'apprenant

```mermaid
flowchart LR
    CLONE[Cloner ce dépôt] --> INSTALL[Installer les outils]
    INSTALL --> CONFIG[Configurer Snowflake]
    CONFIG --> LABS[Suivre les ateliers]
    LABS --> ADD[Créer les fichiers .tf]
    ADD --> VALIDATE[Valider localement]
    VALIDATE --> PIPELINE[Pousser vers le pipeline]
```

## Contenu

```text
.
├── README.md                  # Ce fichier
├── .gitignore                 # Exclut state, plans, secrets, tfvars, .terraform/
├── .gitattributes             # Normalise les fins de ligne
├── .editorconfig              # Convention d'édition
├── .tflint.hcl                # Configuration du linter
├── azure-pipelines.yml        # Pipeline CI/CD Azure DevOps
├── CODEOWNERS                 # Propriété du code et revue obligatoire
├── docs/
│   ├── architecture.md        # Architecture cible
│   ├── naming-conventions.md  # Convention de nommage
│   ├── runbook.md             # Procédures opérationnelles
│   └── adr/                   # Architecture Decision Records
│       └── 0001-record-architecture-decisions.md
├── environments/
│   ├── dev/                   # Racine Terraform DEV
│   ├── uat/                   # Racine Terraform UAT
│   └── prod/                  # Racine Terraform PROD
├── modules/
│   └── README.md              # Modules réutilisables (à créer par l'apprenant)
└── scripts/
    ├── Install-Tools.ps1           # Installation Windows
    ├── install-tools.sh            # Installation Linux/macOS
    ├── Learner-Login.ps1           # Login Azure KV-first Windows
    ├── learner-login.sh            # Login Azure Linux/macOS
    ├── New-SnowflakeConnection.ps1 # Connexion Snowflake Windows
    ├── new-snowflake-connection.sh # Connexion Snowflake Linux/macOS
    ├── Test-LabConnectivity.ps1    # Validation connectivité Windows
    ├── test-lab-connectivity.sh    # Validation connectivité Linux/macOS
    ├── Test-VMReadiness.ps1        # Vérification VM Windows
    ├── validate.ps1                # Validation locale Windows
    └── validate.sh                 # Validation locale Linux/macOS
```

## Démarrage rapide (Jour 0)

### 1. Cloner

```bash
git clone https://github.com/msellamiTN/data-platform-starter.git ~/Data2AI-Labs/data-platform
cd ~/Data2AI-Labs/data-platform
```

### 2. Installer les outils

**Windows :**

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Tools.ps1 -Check
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Tools.ps1
```

**Linux/macOS :**

```bash
chmod +x scripts/install-tools.sh
./scripts/install-tools.sh --check
./scripts/install-tools.sh
```

### 3. Configurer `.env`

Le formateur a pré-rempli `.env.example` avec les paramètres d'accès Snowflake, Azure et Azure DevOps.

```bash
cp .env.example .env
```

Ouvrez `.env` et ajoutez uniquement :

- `LEARNER_PREFIX` : votre préfixe apprenant (fourni par le formateur).

Les autres valeurs sont déjà remplies par le formateur. `.env` est gitignored.

> `[KV-FIRST]` En mode KV-first, vous n'avez **pas besoin** de fichiers
> `secrets/` distribués manuellement. Les secrets (SP credentials, PAT)
> sont récupérés depuis Azure Key Vault par `Learner-Login.ps1`.

### 4. Configurer la connexion Snowflake

**Windows :**

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\New-SnowflakeConnection.ps1
```

**Linux/macOS :**

```bash
./scripts/new-snowflake-connection.sh
```

Le script lit `.env` automatiquement et crée la connexion `training`.

### 5. Authentifier Azure (KV-first)

**Windows :**

```powershell
.\scripts\Learner-Login.ps1 -LearnerPrefix APP01
```

Le script va :
1. Vous authentifier avec votre compte AAD (navigateur)
2. Récupérer les credentials SP + PAT depuis Key Vault
3. Se reconnecter avec le SP pour Terraform
4. Définir toutes les variables d'environnement

**Fallback (recovery uniquement) :**

```powershell
.\scripts\Learner-Login.ps1 -LearnerPrefix APP01 -ForceFallback
```

### 6. Valider

```bash
snow sql -q 'SELECT 1' -c training
.\scripts\Test-LabConnectivity.ps1 -SkipDevOps
```

### 7. Suivre les ateliers

Chaque atelier du parcours indique quels fichiers créer et où. Le dépôt cloné est la **racine de travail** pour tous les fichiers `.tf`, modules et configurations.

## 🧭 Navigation des ateliers

| # | Atelier | Lab (instructions) | Dossier de travail | Objectif |
|---|---------|--------------------|--------------------|----------|
| M00 | Setup | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-00/module-00-setup/lab.md) | — | Préparer l'environnement : outils, connexion Snowflake, login Azure |
| M01 | IaC Workflow | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-01/module-01-iac-workflow/lab.md) | `labs/m01-iac-workflow` | Premier déploiement Terraform : database, schema, warehouse |
| M02 | State Management | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-01/module-02-state-management/lab.md) | `labs/m02-state-management` | State local puis migration vers le backend Azure |
| M03 | Import Brownfield | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-01/module-03-import-brownfield/lab.md) | `labs/m03-import-brownfield` | Importer une ressource existante, dérive, bloc `moved` |
| M04 | Variables & Outputs | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-01/module-04-variables-outputs/lab.md) | `labs/m04-variables-outputs` | Variables validées, précédence, outputs, `lifecycle` |
| M05 | Modules | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-02/module-05-modules/lab.md) | `labs/m05-modules` | Extraire et réutiliser un module `landing-zone` |
| M06 | Dynamic Logic | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-02/module-06-dynamic-logic/lab.md) | `labs/m06-dynamic-logic` | `for_each`, `count`, expressions `for`, blocs `dynamic` |
| M07 | CI/CD Pipeline | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-02/module-07-cicd-pipeline/lab.md) | `labs/m07-cicd-pipeline` | Pipeline Azure DevOps : validate, plan, approval, apply, audit |
| M08 | Environments | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-02/module-08-environments/lab.md) | `labs/m08-environments` | Layout `dev/` `uat/` `prod/` avec backends isolés |
| M09 | Snowflake Advanced | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-03/module-09-snowflake-advanced/lab.md) | `labs/m09-snowflake-advanced` | Ressources Snowflake avancées |
| M10 | Security & Auth | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-03/module-10-security-auth/lab.md) | `labs/m10-security-auth` | Authentification et sécurité |
| M11 | RBAC | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-04/module-11-rbac/lab.md) | `labs/m11-rbac` | Rôles, grants et contrôle d'accès |
| M12 | Capstone | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-04/module-12-capstone/lab.md) | `labs/m12-capstone` | Projet de synthèse |
| M13 | FinOps & Observability | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-04/module-13-finops-observability/lab.md) | `labs/m13-finops-observability` | Coûts, tags et observabilité |
| M14 | Data Products | [lab.md](https://github.com/msellamiTN/Snowflake-terraform/blob/master/courses/day-04/module-14-data-products/lab.md) | `labs/m14-data-products` | Data products de bout en bout |

> 💡 **Astuce** : chaque dossier d'atelier contient un `terraform.tfvars.example`
> à copier en `terraform.tfvars` et un `provider.tf` qui lit le PAT depuis
> `secrets/snowflake_pat.txt` (fallback : `TF_VAR_snowflake_token`).

## Ce qui n'est PAS inclus

- aucun fichier `versions.tf`, `provider.tf`, `main.tf`, `variables.tf` ou `outputs.tf`;
- aucun module Terraform de ressource;
- aucun fichier `.terraform.lock.hcl`;
- aucun state, plan ou secret.

L'apprenant crée ces fichiers au fil du parcours, en suivant les ateliers.

## Convention de nommage

Toutes les ressources suivent :

```text
<PREFIXE_APPRENANT>_<ZONE>_<ENVIRONNEMENT>
```

Exemple : `ABC_RAW_DEV`, `ABC_ETL_UAT`, `ABC_CURATED_PROD`.

Détail dans [docs/naming-conventions.md](docs/naming-conventions.md).

## Versions

Les versions de Terraform et des providers sont définies dans le document de politique de versions du parcours de formation. Aucun fichier `.tf` n'est fourni ici; l'apprenant les crée avec les contraintes exactes indiquées par le formateur.

## Sécurité

- aucun secret, mot de passe, PAT ou clé privée n'est commité;
- les fichiers `.tfvars`, `backend.hcl`, `.env` et `secrets/` sont ignorés par Git;
- le state Terraform est stocké à distance dans Azure Blob Storage;
- les secrets (SP credentials, PAT Snowflake) sont stockés dans Azure Key Vault;
- **modèle KV-first** : les apprenants récupèrent les secrets depuis Key Vault
  via leur compte AAD, aucun secret n'est stocké sur les VMs apprenants;
- les fichiers `secrets/` locaux sont un **fallback de recovery** uniquement.

## Pipeline CI/CD

Le fichier `azure-pipelines.yml` définit les étapes de validation, formatage, lint, plan, approbation, apply et audit de dérive. Il est identique à celui étudié dans le module CI/CD du parcours.
