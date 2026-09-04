Atelier 0 — Préparation complète de l’environnement Terraform & Snowflake
Objectif de l’atelier

À la fin de cet atelier, vous serez capable de :

installer Git for Windows et OpenSSL ;
cloner le repository du cours ;
configurer PowerShell pour exécuter les scripts du lab ;
installer automatiquement tous les outils nécessaires ;
vérifier l’installation de chaque outil ;
valider Terraform ;
vérifier l’accès Azure ;
tester Snowflake CLI ;
ouvrir le projet dans Visual Studio Code ;
diagnostiquer les problèmes de PATH.
Architecture de l’environnement
Windows
│
├── Git for Windows
│   ├── Git
│   └── OpenSSL
│
├── Terraform 1.14.5
│
├── Python 3.12
│   └── Snowflake CLI
│
├── Azure CLI
│
├── TFLint 0.50.0
│
└── Visual Studio Code
    │
    └── snowflake-terraform
1. Préparer PowerShell
1.1 Ouvrir PowerShell

Ouvrez :

Start
→ Windows PowerShell

Pour l'installation initiale, il est recommandé d'utiliser :

Run as Administrator
1.2 Vérifier PowerShell

Exécutez :

$PSVersionTable.PSVersion

Résultat attendu :

Major  Minor  Build  Revision
-----  -----  -----  --------
5      1      ...

Le lab cible Windows PowerShell 5.1.

2. Vérifier l'architecture Windows

Terraform et TFLint utilisent les binaires Windows AMD64.

Exécutez :

[Environment]::Is64BitOperatingSystem

Résultat attendu :

True

Puis :

$env:PROCESSOR_ARCHITECTURE

Résultat attendu :

AMD64
3. Vérifier WinGet

Exécutez :

winget --version

Résultat attendu :

v1.x.x

Si winget est disponible, nous l'utiliserons pour installer Git.

4. Installer Git for Windows
4.1 Installation

Git for Windows fournit également les composants OpenSSL utilisés dans l'environnement du lab.

Exécutez :

winget install --id Git.Git -e --source winget

Attendez la fin de l'installation.

Vous devez obtenir un message similaire à :

Successfully installed
5. Redémarrer PowerShell
Important

Fermez complètement PowerShell.

Ouvrez ensuite une nouvelle fenêtre PowerShell.

Cette étape est importante car les nouveaux programmes et modifications du PATH ne sont pas automatiquement disponibles dans les anciennes sessions.

6. Vérifier Git

Exécutez :

git --version

Exemple :

git version 2.55.0.windows.3

Vérifiez également l'emplacement :

where.exe git

Exemple :

C:\Program Files\Git\cmd\git.exe
7. Vérifier OpenSSL

Exécutez :

openssl version

Exemple :

OpenSSL 3.5.7 ...

Puis :

where.exe openssl

Vous pouvez obtenir :

C:\Program Files\Git\mingw64\bin\openssl.exe
8. Dépannage OpenSSL

Si :

openssl version

retourne :

openssl : The term 'openssl' is not recognized

vérifiez que l'exécutable existe :

Test-Path "C:\Program Files\Git\mingw64\bin\openssl.exe"

Résultat attendu :

True

Ajoutez temporairement le chemin à la session :

$env:PATH = "C:\Program Files\Git\mingw64\bin;$env:PATH"

Puis :

openssl version
9. Configurer Git

Configurez votre identité Git :

git config --global user.name "Votre Nom"
git config --global user.email "votre.email@example.com"

Vérifiez :

git config --global user.name
git config --global user.email
10. Tester la connexion à GitHub

Avant de cloner le projet, testez l'accès au repository :

git ls-remote https://github.com/msellamitn/snowflake-terraform.git

Si GitHub est accessible, vous verrez plusieurs références Git.

11. Créer le répertoire de travail

Déplacez-vous dans votre répertoire utilisateur :

cd $HOME

Créez le répertoire de formation :

New-Item -ItemType Directory -Path "$HOME\training" -Force

Entrez dans celui-ci :

cd "$HOME\training"
12. Cloner le repository

Exécutez :

git clone https://github.com/msellamitn/snowflake-terraform.git

Vous devez obtenir quelque chose comme :

Cloning into 'snowflake-terraform'...
Receiving objects...
Resolving deltas...
13. Entrer dans le projet
cd snowflake-terraform

Vérifiez votre emplacement :

Get-Location

Puis :

git status
14. Vérifier le remote Git

Exécutez :

git remote -v

Vous devez retrouver :

origin  https://github.com/msellamitn/snowflake-terraform.git
15. Explorer le repository

Affichez le contenu :

Get-ChildItem

Puis :

Get-ChildItem .\scripts

Le répertoire scripts doit contenir notamment :

Install-LabEnvironment.ps1
Test-LabEnvironment.ps1
16. Autoriser les scripts PowerShell

Nous ne modifions pas la politique globale de Windows.

Autorisez uniquement les scripts dans la session courante :

Set-ExecutionPolicy -Scope Process Bypass

Vérifiez :

Get-ExecutionPolicy

Résultat :

Bypass
17. Vérifier le script d'installation

Avant de lancer le script :

Test-Path .\scripts\Install-LabEnvironment.ps1

Résultat attendu :

True

Vous pouvez inspecter le script :

Get-Content .\scripts\Install-LabEnvironment.ps1

Ou l'ouvrir dans VS Code :

code .\scripts\Install-LabEnvironment.ps1
18. Installer l'environnement complet

Exécutez :

.\scripts\Install-LabEnvironment.ps1

Le script doit installer ou vérifier :

1/8 Terraform
2/8 Python
3/8 Snowflake CLI
4/8 Git
5/8 OpenSSL
6/8 VS Code
7/8 Azure CLI
8/8 TFLint
19. Vérifier le résultat de l'installation

À la fin, recherchez :

[OK] Terraform
[OK] Python
[OK] Snowflake CLI
[OK] Git
[OK] OpenSSL
[OK] VS Code
[OK] Azure CLI
[OK] TFLint

Vous devez obtenir :

INSTALLATION TERMINEE AVEC SUCCES
20. Redémarrer PowerShell
Très important

Fermez PowerShell.

Ouvrez une nouvelle fenêtre PowerShell.

Revenez dans le projet :

cd $HOME\training\snowflake-terraform
21. Vérification automatique de l'environnement

Le repository contient le script :

.\scripts\Test-LabEnvironment.ps1

Exécutez-le :

.\scripts\Test-LabEnvironment.ps1

Le script vérifie notamment :

les commandes disponibles ;
les versions ;
les chemins d'installation ;
Git ;
OpenSSL ;
Python ;
Snowflake CLI ;
Azure CLI ;
Terraform ;
TFLint ;
VS Code ;
les extensions VS Code ;
le repository Git ;
la configuration Terraform.
22. Vérification manuelle des outils

Même si le script automatique passe, nous allons effectuer une validation manuelle.

Terraform
terraform version

Attendu :

Terraform v1.14.5

Puis :

where.exe terraform
Python
python --version

Attendu :

Python 3.12.x

Puis :

where.exe python
Snowflake CLI
snow --version

Puis :

where.exe snow
Git
git --version

Puis :

where.exe git
OpenSSL
openssl version

Puis :

where.exe openssl
VS Code
code --version
Azure CLI
az version

Vous pouvez obtenir uniquement la version :

az version --query '"azure-cli"' -o tsv
TFLint
tflint --version

Attendu :

TFLint version 0.50.0
23. Vérification globale en une commande

Vous pouvez utiliser ce contrôle rapide :

$tools = @(
    "git",
    "openssl",
    "terraform",
    "python",
    "snow",
    "az",
    "tflint",
    "code"
)

foreach ($tool in $tools) {
    if (Get-Command $tool -ErrorAction SilentlyContinue) {
        Write-Host "[OK] $tool" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] $tool" -ForegroundColor Red
    }
}

Résultat attendu :

[OK] git
[OK] openssl
[OK] terraform
[OK] python
[OK] snow
[OK] az
[OK] tflint
[OK] code
24. Vérifier Terraform dans le projet

Recherchez les fichiers Terraform :

Get-ChildItem -Recurse -Filter *.tf
25. Initialiser Terraform

Exécutez :

terraform init

Résultat attendu :

Terraform has been successfully initialized!
26. Valider Terraform

Exécutez :

terraform validate

Résultat attendu :

Success! The configuration is valid.
27. Formater Terraform

Exécutez :

terraform fmt -recursive

Puis vérifiez :

terraform fmt -recursive -check
28. Vérifier TFLint

Cherchez la configuration :

Get-ChildItem -Force

Si .tflint.hcl existe :

tflint --init

Puis :

tflint
29. Vérifier Azure CLI

Vérifiez si vous êtes connecté :

az account show

Si aucune session n'est disponible :

az login

Puis :

az account show
30. Afficher les abonnements Azure
az account list -o table

Identifiez l'abonnement fourni pour la formation.

31. Sélectionner l'abonnement
az account set --subscription "<SUBSCRIPTION_NAME_OR_ID>"

Vérifiez :

az account show -o table
32. Vérifier Snowflake CLI

Affichez l'aide :

snow --help

Puis :

snow connection list

Selon la configuration du cours, une connexion Snowflake devra ensuite être configurée.

33. Vérifier la configuration Snowflake
Test-Path "$HOME\.snowflake"

Puis, si le dossier existe :

Get-ChildItem "$HOME\.snowflake" -Force
34. Ouvrir le projet dans VS Code

Exécutez :

code .
35. Vérifier les extensions VS Code
code --list-extensions

Les extensions suivantes sont recommandées :

HashiCorp.terraform
ms-azuretools.vscode-azureterraform
ms-python.python
redhat.vscode-yaml
shd101wyy.markdown-preview-enhanced
36. Diagnostic PATH

Si une commande fonctionne dans le script mais pas directement après l'installation, vérifiez le PATH.

Affichez-le :

$env:PATH -split ";"

Cherchez notamment :

C:\tools\tf-bin
C:\tools\tflint-bin

Pour le PATH utilisateur permanent :

[Environment]::GetEnvironmentVariable("PATH","User") -split ";"
37. Diagnostic direct de Terraform

Même si terraform n'est pas trouvé par le terminal, testez directement :

C:\tools\tf-bin\terraform.exe version

Si cette commande fonctionne mais :

terraform version

échoue, le problème est uniquement le PATH.

38. Diagnostic direct de TFLint
C:\tools\tflint-bin\tflint.exe --version

Même principe : si l'exécutable fonctionne directement mais pas tflint, il faut corriger ou rafraîchir le PATH.

39. Procédure de récupération après installation

Si un outil affiche :

The term 'terraform' is not recognized

ne réinstallez pas immédiatement.

Étape 1

Fermez PowerShell.

Étape 2

Ouvrez une nouvelle session.

Étape 3

Testez :

terraform version
Étape 4

Si le problème persiste :

where.exe terraform
Étape 5

Vérifiez le fichier :

Test-Path C:\tools\tf-bin\terraform.exe
Étape 6

Refaites la même procédure avec :

where.exe python
where.exe snow
where.exe openssl
where.exe az
where.exe tflint
40. Validation finale de l'atelier

Exécutez successivement :

terraform version
python --version
snow --version
git --version
openssl version
code --version
az version
tflint --version

Puis :

terraform init

Puis :

terraform validate

Puis :

.\scripts\Test-LabEnvironment.ps1
Critères de réussite

L'atelier est terminé lorsque vous obtenez :

[OK] Terraform
[OK] Python
[OK] Snowflake CLI
[OK] Git
[OK] OpenSSL
[OK] VS Code
[OK] Azure CLI
[OK] TFLint

et :

Environment status: READY

et :

Success! The configuration is valid.
Quick Start

Pour une nouvelle machine Windows, la procédure minimale est :

# 1. Installer Git + OpenSSL
winget install --id Git.Git -e --source winget

# 2. Fermer et rouvrir PowerShell

# 3. Vérifier Git
git --version
openssl version

# 4. Cloner le projet
cd $HOME
New-Item -ItemType Directory -Path "$HOME\training" -Force
cd "$HOME\training"

git clone https://github.com/msellamitn/snowflake-terraform.git

# 5. Entrer dans le projet
cd snowflake-terraform

# 6. Autoriser les scripts pour cette session
Set-ExecutionPolicy -Scope Process Bypass

# 7. Installer l'environnement
.\scripts\Install-LabEnvironment.ps1

# 8. Fermer et rouvrir PowerShell

# 9. Vérifier
.\scripts\Test-LabEnvironment.ps1

# 10. Initialiser Terraform
terraform init

# 11. Valider
terraform validate

# 12. Ouvrir VS Code
code .
Livrable de l'atelier

À la fin de l'atelier, votre poste doit être dans cet état :

snowflake-terraform/
│
├── scripts/
│   ├── Install-LabEnvironment.ps1
│   └── Test-LabEnvironment.ps1
│
├── Terraform configuration
├── Snowflake configuration
├── Documentation
└── Git repository

Votre environnement est alors prêt pour les ateliers suivants : Terraform, Azure Infrastructure as Code, Snowflake Infrastructure as Code, Terraform State, Variables, Modules, CI/CD et Industrialisation Data Platform.