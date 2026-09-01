#requires -version 5.1
<#
.SYNOPSIS
    Tests connectivity to all services used in the training labs.

.DESCRIPTION
    Verifies that the learner can reach:
    - Snowflake (via snow CLI connection)
    - Azure CLI (authenticated session)
    - Azure Blob Storage (Terraform backend)
    - Azure Key Vault (secret storage)
    - Azure DevOps (CI/CD pipelines)
    - Git (local and remote)
    - Terraform (initialized provider)

    Reads .env from the project root for connection parameters.
    The PAT is read from secrets/snowflake_pat.txt (never displayed).

.PARAMETER SkipAzure
    Skip Azure connectivity tests (useful if Azure is not yet configured).

.PARAMETER SkipDevOps
    Skip Azure DevOps connectivity tests.

.PARAMETER ReportPath
    Base path for the report. Two files are written: .md and .json.
    Defaults to reports/connectivity under the project root.
    No credential is ever written to a report.

.EXAMPLE
    .\scripts\Test-LabConnectivity.ps1
    .\scripts\Test-LabConnectivity.ps1 -SkipAzure -SkipDevOps
    .\scripts\Test-LabConnectivity.ps1 -ReportPath .\reports\connectivity
#>

[CmdletBinding()]
param(
    [switch]$SkipAzure,
    [switch]$SkipDevOps,
    [string]$ReportPath
)

# Default report path: reports/connectivity under the project root
if (-not $ReportPath) {
    $ReportPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'reports\connectivity'
}

$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'

# ------------------------------------------------------------------
# Load .env
# ------------------------------------------------------------------

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$envFile = Join-Path $projectRoot '.env'

$envValues = @{}

if (Test-Path $envFile) {
    Write-Host "[INFO] Loading .env from $envFile" -ForegroundColor DarkGray
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and $line -notmatch '^#') {
            $sep = $line.IndexOf('=')
            if ($sep -gt 0) {
                $key = $line.Substring(0, $sep).Trim()
                $value = $line.Substring($sep + 1).Trim().Trim('"').Trim("'")
                $envValues[$key] = $value
            }
        }
    }
} else {
    Write-Host "[WARN] No .env file found at $envFile" -ForegroundColor Yellow
    Write-Host "       Copy .env.example to .env and fill in your values." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

function Get-ConfigValue {
    param([string]$Key, [string]$Default = '')
    if ($envValues.ContainsKey($Key) -and $envValues[$Key]) { return $envValues[$Key] }
    if ($Default) { return $Default }
    return ''
}

$passCount = 0
$failCount = 0
$warnCount = 0
$skipCount = 0

$Results = [System.Collections.Generic.List[object]]::new()
$currentSection = ''

function Set-Section {
    param([string]$Name)
    $script:currentSection = $Name
}

function Test-Step {
    param(
        [string]$Name,
        [ValidateSet('PASS','FAIL','WARN','SKIP')][string]$Status,
        [string]$Detail = ''
    )

    $color = switch ($Status) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'WARN' { 'Yellow' }
        'SKIP' { 'DarkGray' }
    }

    Write-Host ("  [{0}] {1}" -f $Status, $Name) -ForegroundColor $color
    if ($Detail) {
        Write-Host "         $Detail" -ForegroundColor DarkGray
    }

    $script:Results.Add([PSCustomObject]@{
        Section = $script:currentSection
        Name    = $Name
        Status  = $Status
        Detail  = $Detail
    })

    switch ($Status) {
        'PASS' { $script:passCount++ }
        'FAIL' { $script:failCount++ }
        'WARN' { $script:warnCount++ }
        'SKIP' { $script:skipCount++ }
    }
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# ------------------------------------------------------------------
# Header
# ------------------------------------------------------------------

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Lab Connectivity Test' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

# ------------------------------------------------------------------
# 1. CLI tools presence
# ------------------------------------------------------------------

Set-Section '1. CLI Tools'
Write-Host '== 1. CLI Tools' -ForegroundColor Cyan

if (Test-Command 'git') {
    $gitVer = (& git --version) 2>&1
    Test-Step 'Git' 'PASS' $gitVer
} else {
    Test-Step 'Git' 'FAIL' 'Not found'
}

if (Test-Command 'terraform') {
    $tfVer = (& terraform version) 2>&1 | Select-Object -First 1
    Test-Step 'Terraform' 'PASS' $tfVer
} else {
    Test-Step 'Terraform' 'FAIL' 'Not found'
}

if (Test-Command 'snow') {
    $snowVer = (& snow --version) 2>&1 | Select-Object -First 1
    Test-Step 'Snowflake CLI' 'PASS' $snowVer
} else {
    Test-Step 'Snowflake CLI' 'FAIL' 'Not found'
}

if (Test-Command 'az') {
    Test-Step 'Azure CLI' 'PASS' 'Available'
} else {
    Test-Step 'Azure CLI' 'FAIL' 'Not found'
}

if (Test-Command 'python') {
    $pyVer = (& python --version) 2>&1
    Test-Step 'Python' 'PASS' $pyVer
} else {
    Test-Step 'Python' 'FAIL' 'Not found'
}

if (Test-Command 'dbt') {
    $dbtVer = (& dbt --version) 2>&1 | Select-Object -First 1
    Test-Step 'dbt' 'PASS' $dbtVer
} else {
    Test-Step 'dbt' 'WARN' 'Not found (required from Day 4)'
}

if (Test-Command 'tflint') {
    Test-Step 'tflint' 'PASS' 'Available'
} else {
    Test-Step 'tflint' 'WARN' 'Not found (optional)'
}

# ------------------------------------------------------------------
# 2. Snowflake connectivity
# ------------------------------------------------------------------

Write-Host ''
Set-Section '2. Snowflake Connectivity'
Write-Host '== 2. Snowflake Connectivity' -ForegroundColor Cyan

$connectionName = Get-ConfigValue 'SNOWFLAKE_CONNECTION' 'training'

# Check that the connection exists in snow CLI config
$snowConfigDir = Join-Path $env:LOCALAPPDATA 'snowflake'
$snowConfigFile = Join-Path $snowConfigDir 'config.toml'

if (Test-Path $snowConfigFile) {
    $configContent = Get-Content $snowConfigFile -Raw
    if ($configContent -match "connections\.$connectionName\b") {
        Test-Step "Snow CLI connection '$connectionName'" 'PASS' 'Found in config.toml'
    } else {
        Test-Step "Snow CLI connection '$connectionName'" 'FAIL' 'Not found in config.toml - run New-SnowflakeConnection.ps1'
    }
} else {
    Test-Step "Snow CLI connection '$connectionName'" 'FAIL' "No config.toml at $snowConfigFile"
}

# Check that the PAT file exists
$patFileRel = Get-ConfigValue 'SNOWFLAKE_PAT_FILE' 'secrets/snowflake_pat.txt'
$patFilePath = Join-Path $projectRoot $patFileRel

if (Test-Path $patFilePath) {
    $patContent = (Get-Content $patFilePath -Raw).Trim()
    if ($patContent.Length -gt 10) {
        $patDetail = '{0} ({1} chars)' -f $patFileRel, $patContent.Length
        Test-Step 'PAT file' 'PASS' $patDetail
    } else {
        Test-Step 'PAT file' 'FAIL' ($patFileRel + ' appears empty')
    }
} else {
    Test-Step 'PAT file' 'FAIL' ($patFileRel + ' not found')
}

# Test actual Snowflake query
if (Test-Command 'snow') {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $snowResult = & snow sql -q 'SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT()' -c $connectionName --format=json 2>&1
        $snowExit = $LASTEXITCODE

        $cleanResult = ($snowResult | Where-Object { "$_" -notmatch 'Warning|UserWarning|encoding' })

        if ($snowExit -eq 0 -and $cleanResult) {
            Test-Step 'Snowflake query' 'PASS' $cleanResult
        } else {
            Test-Step 'Snowflake query' 'FAIL' "Exit code $snowExit - check connection and PAT"
        }
    } catch {
        Test-Step 'Snowflake query' 'FAIL' $_.Exception.Message
    } finally {
        $ErrorActionPreference = $prevEAP
    }
} else {
    Test-Step 'Snowflake query' 'SKIP' 'snow CLI not installed'
}

# ------------------------------------------------------------------
# 3. Azure connectivity
# ------------------------------------------------------------------

Write-Host ''
Set-Section '3. Azure Connectivity'
Write-Host '== 3. Azure Connectivity' -ForegroundColor Cyan

if ($SkipAzure) {
    Test-Step 'Azure tests' 'SKIP' 'Skipped by -SkipAzure'
} elseif (-not (Test-Command 'az')) {
    Test-Step 'Azure tests' 'SKIP' 'Azure CLI not installed'
} else {
    # -- 3a. Azure CLI authentication --
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $azAccount = & az account show --query 'name' -o tsv 2>&1
        $azExit = $LASTEXITCODE

        if ($azExit -eq 0 -and $azAccount) {
            $azSubId = & az account show --query 'id' -o tsv 2>&1
            $azTenant = & az account show --query 'tenantId' -o tsv 2>&1
            Test-Step 'Azure CLI authentication' 'PASS' "Subscription: $azAccount ($azSubId)"
            Test-Step 'Azure tenant' 'PASS' "Tenant: $azTenant"
        } else {
            Test-Step 'Azure CLI authentication' 'FAIL' "Not logged in - run 'az login'"
        }
    } catch {
        Test-Step 'Azure CLI authentication' 'FAIL' $_.Exception.Message
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    # -- 3b. Azure subscription match --
    $armSubId = Get-ConfigValue 'ARM_SUBSCRIPTION_ID'
    if ($armSubId) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $currentSubId = & az account show --query 'id' -o tsv 2>&1
            if ($currentSubId -eq $armSubId) {
                Test-Step 'Subscription match' 'PASS' 'Current subscription matches ARM_SUBSCRIPTION_ID'
            } else {
                Test-Step 'Subscription match' 'WARN' "Current sub=$currentSubId, .env expects=$armSubId - run 'az account set --subscription $armSubId'"
            }
        } catch {
            Test-Step 'Subscription match' 'WARN' 'Could not compare'
        } finally {
            $ErrorActionPreference = $prevEAP
        }
    } else {
        Test-Step 'Subscription match' 'SKIP' 'ARM_SUBSCRIPTION_ID not set in .env'
    }

    # -- 3c. Azure service principal --
    $armClientId = Get-ConfigValue 'ARM_CLIENT_ID'
    $armTenantId = Get-ConfigValue 'ARM_TENANT_ID'
    if ($armClientId -and $armTenantId) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $spCheck = & az ad sp show --id $armClientId --query 'appId' -o tsv 2>&1
            if ($LASTEXITCODE -eq 0 -and $spCheck) {
                Test-Step 'Service principal' 'PASS' "App ID: $armClientId"
            } else {
                Test-Step 'Service principal' 'FAIL' "SP not found: $armClientId - check ARM_CLIENT_ID"
            }
        } catch {
            Test-Step 'Service principal' 'WARN' 'Could not verify SP (may lack Graph permissions)'
        } finally {
            $ErrorActionPreference = $prevEAP
        }
    } else {
        Test-Step 'Service principal' 'SKIP' 'ARM_CLIENT_ID or ARM_TENANT_ID not set in .env'
    }

    # -- 3d. Azure resource group --
    $armResourceGroup = Get-ConfigValue 'ARM_RESOURCE_GROUP'
    if ($armResourceGroup) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $rgCheck = & az group show --name $armResourceGroup --query 'name' -o tsv 2>&1
            if ($LASTEXITCODE -eq 0 -and $rgCheck) {
                $rgLocation = & az group show --name $armResourceGroup --query 'location' -o tsv 2>&1
                Test-Step 'Resource group' 'PASS' "$armResourceGroup ($rgLocation)"
            } else {
                Test-Step 'Resource group' 'FAIL' "Not found: $armResourceGroup"
            }
        } catch {
            Test-Step 'Resource group' 'FAIL' $_.Exception.Message
        } finally {
            $ErrorActionPreference = $prevEAP
        }
    } else {
        Test-Step 'Resource group' 'SKIP' 'ARM_RESOURCE_GROUP not set in .env'
    }

    # -- 3e. Azure Storage Account and Blob container --
    $armStorageAccount = Get-ConfigValue 'ARM_STORAGE_ACCOUNT'
    $armContainer = Get-ConfigValue 'ARM_CONTAINER' 'tfstate'
    if ($armStorageAccount -and $armResourceGroup) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $saCheck = & az storage account show --name $armStorageAccount --resource-group $armResourceGroup --query 'name' -o tsv 2>&1
            if ($LASTEXITCODE -eq 0 -and $saCheck) {
                $saSku = & az storage account show --name $armStorageAccount --resource-group $armResourceGroup --query 'sku.name' -o tsv 2>&1
                Test-Step 'Azure Storage Account' 'PASS' "$armStorageAccount (SKU: $saSku)"

                # Check container
                $containerCheck = & az storage container exists --name $armContainer --account-name $armStorageAccount --query 'exists' -o tsv 2>&1
                if ($LASTEXITCODE -eq 0 -and $containerCheck -eq 'True') {
                    Test-Step 'Azure Blob Container' 'PASS' $armContainer
                } else {
                    Test-Step 'Azure Blob Container' 'WARN' "Container '$armContainer' not found - will be created by terraform init"
                }

                # Test write access (create a small probe blob, then delete it)
                $probeName = 'connectivity-probe-' + (Get-Date -Format 'yyyyMMddHHmmss') + '.txt'
                $probeTemp = Join-Path $env:TEMP $probeName
                'connectivity-test' | Set-Content $probeTemp -Encoding utf8
                $uploadResult = & az storage blob upload --account-name $armStorageAccount --container-name $armContainer --name $probeName --file $probeTemp --overwrite true 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Test-Step 'Blob write access' 'PASS' 'Probe uploaded and deleted'
                    & az storage blob delete --account-name $armStorageAccount --container-name $armContainer --name $probeName 2>&1 | Out-Null
                    Remove-Item $probeTemp -Force -ErrorAction SilentlyContinue
                } else {
                    Test-Step 'Blob write access' 'FAIL' 'Cannot write to container - check RBAC or access keys'
                    Remove-Item $probeTemp -Force -ErrorAction SilentlyContinue
                }
            } else {
                Test-Step 'Azure Storage Account' 'FAIL' "Not found: $armStorageAccount in $armResourceGroup"
            }
        } catch {
            Test-Step 'Azure Storage Account' 'FAIL' $_.Exception.Message
        } finally {
            $ErrorActionPreference = $prevEAP
        }
    } else {
        Test-Step 'Azure Storage Account' 'SKIP' 'ARM_STORAGE_ACCOUNT or ARM_RESOURCE_GROUP not set in .env'
    }

    # -- 3f. Azure Key Vault --
    $kvName = Get-ConfigValue 'KEY_VAULT_NAME'
    $kvRg = Get-ConfigValue 'KEY_VAULT_RESOURCE_GROUP'
    if ($kvName) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $kvCheck = & az keyvault show --name $kvName --resource-group $kvRg --query 'name' -o tsv 2>&1
            if ($LASTEXITCODE -eq 0 -and $kvCheck) {
                $kvUri = & az keyvault show --name $kvName --resource-group $kvRg --query 'properties.vaultUri' -o tsv 2>&1
                Test-Step 'Azure Key Vault' 'PASS' "$kvName ($kvUri)"

                # List secrets (just names, not values)
                $secretList = & az keyvault secret list --vault-name $kvName --query '[].name' -o tsv 2>&1
                if ($LASTEXITCODE -eq 0 -and $secretList) {
                    $secretCount = ($secretList -split "`t").Count
                    Test-Step 'Key Vault secrets' 'PASS' "$secretCount secret(s) accessible"
                } else {
                    Test-Step 'Key Vault secrets' 'WARN' 'No secrets or no access - check RBAC'
                }
            } else {
                Test-Step 'Azure Key Vault' 'WARN' "Not found: $kvName (used from Day 4 - may not exist yet)"
            }
        } catch {
            Test-Step 'Azure Key Vault' 'WARN' 'Cannot verify (used from Day 4)'
        } finally {
            $ErrorActionPreference = $prevEAP
        }
    } else {
        Test-Step 'Azure Key Vault' 'SKIP' 'KEY_VAULT_NAME not set in .env'
    }
}

# ------------------------------------------------------------------
# 4. Azure DevOps connectivity
# ------------------------------------------------------------------

Write-Host ''
Set-Section '4. Azure DevOps Connectivity'
Write-Host '== 4. Azure DevOps Connectivity' -ForegroundColor Cyan

if ($SkipDevOps) {
    Test-Step 'Azure DevOps tests' 'SKIP' 'Skipped by -SkipDevOps'
} else {
    $adoOrg = Get-ConfigValue 'ADO_ORGANIZATION'
    $adoProject = Get-ConfigValue 'ADO_PROJECT'
    $adoServiceConnection = Get-ConfigValue 'ADO_SERVICE_CONNECTION'

    if (-not $adoOrg -or $adoOrg -match '^<') {
        Test-Step 'Azure DevOps' 'SKIP' 'ADO_ORGANIZATION not set in .env (used from Day 5)'
    } elseif (-not (Test-Command 'az')) {
        Test-Step 'Azure DevOps' 'SKIP' 'Azure CLI required for DevOps tests'
    } else {
        # -- 4a. Azure DevOps CLI extension --
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $extCheck = & az extension list --query "[?name=='azure-devops'].name" -o tsv 2>&1
            if ($LASTEXITCODE -eq 0 -and $extCheck) {
                Test-Step 'Azure DevOps CLI extension' 'PASS' 'azure-devops installed'
            } else {
                Test-Step 'Azure DevOps CLI extension' 'WARN' 'Not installed - run: az extension add --name azure-devops'
            }
        } catch {
            Test-Step 'Azure DevOps CLI extension' 'WARN' 'Could not check extension'
        } finally {
            $ErrorActionPreference = $prevEAP
        }

        # -- 4b. DevOps organization URL --
        $adoOrgUrl = if ($adoOrg -match '^https?://') { $adoOrg } else { "https://dev.azure.com/$adoOrg" }
        Test-Step 'DevOps organization URL' 'PASS' $adoOrgUrl

        # -- 4c. DevOps PAT (check if AZURE_DEVOPS_EXT_PAT is set) --
        if ($env:AZURE_DEVOPS_EXT_PAT) {
            Test-Step 'DevOps PAT' 'PASS' 'AZURE_DEVOPS_EXT_PAT is set'
        } else {
            Test-Step 'DevOps PAT' 'WARN' 'AZURE_DEVOPS_EXT_PAT not set - run: $env:AZURE_DEVOPS_EXT_PAT = "<your-pat>"'
        }

        # -- 4d. DevOps project (REST API call) --
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $encodedProject = [uri]::EscapeDataString($adoProject)
            $apiUrl = "$adoOrgUrl/_apis/projects/$encodedProject?api-version=7.1"

            if ($env:AZURE_DEVOPS_EXT_PAT) {
                $pat = $env:AZURE_DEVOPS_EXT_PAT
                $token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$pat"))
                $headers = @{ Authorization = "Basic $token" }
                $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get -ErrorAction Stop
                if ($response -and $response.name) {
                    Test-Step 'DevOps project' 'PASS' "Project: $($response.name) (id: $($response.id))"
                } else {
                    Test-Step 'DevOps project' 'WARN' 'Project not found or no access'
                }
            } else {
                Test-Step 'DevOps project' 'SKIP' 'Set AZURE_DEVOPS_EXT_PAT to test project access'
            }
        } catch {
            $errMsg = $_.Exception.Message
            if ($errMsg -match '401|Unauthorized') {
                Test-Step 'DevOps project' 'FAIL' 'Unauthorized - check PAT permissions'
            } elseif ($errMsg -match '404') {
                Test-Step 'DevOps project' 'FAIL' "Project not found: $adoProject"
            } else {
                Test-Step 'DevOps project' 'WARN' "Cannot verify: $errMsg"
            }
        } finally {
            $ErrorActionPreference = $prevEAP
        }

        # -- 4e. DevOps repositories (REST API call) --
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            if ($env:AZURE_DEVOPS_EXT_PAT -and $adoProject) {
                $encodedProject = [uri]::EscapeDataString($adoProject)
                $repoUrl = "$adoOrgUrl/$encodedProject/_apis/git/repositories?api-version=7.1"
                $pat = $env:AZURE_DEVOPS_EXT_PAT
                $token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$pat"))
                $headers = @{ Authorization = "Basic $token" }
                $repoResponse = Invoke-RestMethod -Uri $repoUrl -Headers $headers -Method Get -ErrorAction Stop
                $repoCount = $repoResponse.count
                if ($repoCount -gt 0) {
                    $repoNames = ($repoResponse.value | Select-Object -First 3 -ExpandProperty name) -join ', '
                    Test-Step 'DevOps repositories' 'PASS' "$repoCount repo(s): $repoNames"
                } else {
                    Test-Step 'DevOps repositories' 'WARN' 'No repositories found in project'
                }
            } else {
                Test-Step 'DevOps repositories' 'SKIP' 'Set AZURE_DEVOPS_EXT_PAT to test repo access'
            }
        } catch {
            Test-Step 'DevOps repositories' 'WARN' 'Cannot verify repositories'
        } finally {
            $ErrorActionPreference = $prevEAP
        }

        # -- 4f. DevOps pipelines (REST API call) --
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            if ($env:AZURE_DEVOPS_EXT_PAT -and $adoProject) {
                $encodedProject = [uri]::EscapeDataString($adoProject)
                $pipeUrl = "$adoOrgUrl/$encodedProject/_apis/pipelines?api-version=7.1"
                $pat = $env:AZURE_DEVOPS_EXT_PAT
                $token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$pat"))
                $headers = @{ Authorization = "Basic $token" }
                $pipeResponse = Invoke-RestMethod -Uri $pipeUrl -Headers $headers -Method Get -ErrorAction Stop
                $pipeCount = $pipeResponse.count
                if ($pipeCount -gt 0) {
                    Test-Step 'DevOps pipelines' 'PASS' "$pipeCount pipeline(s) found"
                } else {
                    Test-Step 'DevOps pipelines' 'WARN' 'No pipelines found - will be created in Day 5'
                }
            } else {
                Test-Step 'DevOps pipelines' 'SKIP' 'Set AZURE_DEVOPS_EXT_PAT to test pipeline access'
            }
        } catch {
            Test-Step 'DevOps pipelines' 'WARN' 'Cannot verify pipelines (may not exist yet)'
        } finally {
            $ErrorActionPreference = $prevEAP
        }

        # -- 4g. Service connection --
        if ($adoServiceConnection) {
            Test-Step 'Service connection' 'PASS' "Configured: $adoServiceConnection"
        } else {
            Test-Step 'Service connection' 'SKIP' 'ADO_SERVICE_CONNECTION not set in .env'
        }
    }
}

# ------------------------------------------------------------------
# 5. Git and repository
# ------------------------------------------------------------------

Write-Host ''
Set-Section '5. Git and Repository'
Write-Host '== 5. Git and Repository' -ForegroundColor Cyan

if (Test-Path (Join-Path $projectRoot '.git')) {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $gitRemote = & git -C $projectRoot remote get-url origin 2>&1
        if ($LASTEXITCODE -eq 0 -and $gitRemote) {
            Test-Step 'Git remote' 'PASS' $gitRemote
        } else {
            Test-Step 'Git remote' 'WARN' 'No origin remote configured'
        }

        $gitBranch = & git -C $projectRoot branch --show-current 2>&1
        if ($LASTEXITCODE -eq 0 -and $gitBranch) {
            Test-Step 'Git branch' 'PASS' $gitBranch
        } else {
            Test-Step 'Git branch' 'WARN' 'Could not determine current branch'
        }
    } catch {
        Test-Step 'Git remote' 'WARN' $_.Exception.Message
    } finally {
        $ErrorActionPreference = $prevEAP
    }
} else {
    Test-Step 'Git repository' 'WARN' 'Not a git repository (cloned without .git?)'
}

# Check .env is gitignored
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $envIgnored = & git -C $projectRoot check-ignore .env 2>&1
    if ($LASTEXITCODE -eq 0) {
        Test-Step '.env is gitignored' 'PASS' 'Protected'
    } else {
        Test-Step '.env is gitignored' 'FAIL' '.env is NOT ignored - fix .gitignore'
    }
} catch {
    Test-Step '.env is gitignored' 'WARN' 'Could not verify'
} finally {
    $ErrorActionPreference = $prevEAP
}

# Check secrets/ is gitignored
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $secretsIgnored = & git -C $projectRoot check-ignore secrets/snowflake_pat.txt 2>&1
    if ($LASTEXITCODE -eq 0) {
        Test-Step 'secrets/ is gitignored' 'PASS' 'Protected'
    } else {
        Test-Step 'secrets/ is gitignored' 'FAIL' 'secrets/ is NOT ignored - fix .gitignore'
    }
} catch {
    Test-Step 'secrets/ is gitignored' 'WARN' 'Could not verify'
} finally {
    $ErrorActionPreference = $prevEAP
}

# ------------------------------------------------------------------
# 6. Terraform initialization (if .tf files exist)
# ------------------------------------------------------------------

Write-Host ''
Set-Section '6. Terraform Environment'
Write-Host '== 6. Terraform Environment' -ForegroundColor Cyan

$devDir = Join-Path $projectRoot 'environments\dev'
$tfFiles = Get-ChildItem $devDir -Filter '*.tf' -File -ErrorAction SilentlyContinue

if ($tfFiles) {
    Test-Step 'Terraform files in environments/dev' 'PASS' "$($tfFiles.Count) .tf files"

    # Check if terraform is initialized
    $tfDir = Join-Path $devDir '.terraform'
    if (Test-Path $tfDir) {
        Test-Step 'Terraform init' 'PASS' '.terraform/ exists'

        # Check provider lock
        $lockFile = Join-Path $devDir '.terraform.lock.hcl'
        if (Test-Path $lockFile) {
            Test-Step 'Provider lock file' 'PASS' '.terraform.lock.hcl exists'
        } else {
            Test-Step 'Provider lock file' 'WARN' 'No .terraform.lock.hcl'
        }
    } else {
        Test-Step 'Terraform init' 'WARN' 'Not initialized - run terraform init in environments/dev'
    }
} else {
    Test-Step 'Terraform files in environments/dev' 'SKIP' 'No .tf files yet (Day 1 not started)'
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Summary' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "  PASS : $passCount" -ForegroundColor Green
Write-Host "  FAIL : $failCount" -ForegroundColor Red
Write-Host "  WARN : $warnCount" -ForegroundColor Yellow
Write-Host "  SKIP : $skipCount" -ForegroundColor DarkGray
Write-Host ''

# ------------------------------------------------------------------
# Determine overall status
# ------------------------------------------------------------------

$overallStatus = if ($failCount -gt 0) {
    'NOT READY'
} elseif ($warnCount -gt 0) {
    'READY (with warnings)'
} else {
    'READY'
}

# ------------------------------------------------------------------
# Report (always written to reports/connectivity.md and .json)
# ------------------------------------------------------------------

$markdownPath = "$ReportPath.md"
$jsonPath     = "$ReportPath.json"

$reportDir = Split-Path -Parent $markdownPath
if ($reportDir -and -not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Lab Connectivity Report')
$lines.Add('')
$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("Project: $projectRoot")
$lines.Add("Status: $overallStatus")
$lines.Add('')
$lines.Add("| Section | Name | Status | Detail |")
$lines.Add("|---|---|---|---|")
foreach ($item in $Results) {
    $cleanDetail = ($item.Detail -replace '\|', '/') -replace '\s+', ' '
    if ($cleanDetail.Length -gt 100) { $cleanDetail = $cleanDetail.Substring(0, 100) }
    $lines.Add(("| {0} | {1} | {2} | {3} |" -f $item.Section, $item.Name, $item.Status, $cleanDetail))
}
$lines.Add('')
$lines.Add("PASS: $passCount | FAIL: $failCount | WARN: $warnCount | SKIP: $skipCount")

$lines | Set-Content -Path $markdownPath -Encoding utf8

$reportObject = [PSCustomObject]@{
    generated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    project   = $projectRoot
    status    = $overallStatus
    summary   = @{
        PASS = $passCount
        FAIL = $failCount
        WARN = $warnCount
        SKIP = $skipCount
    }
    results   = $Results
}
$reportObject | ConvertTo-Json -Depth 4 | Set-Content -Path $jsonPath -Encoding utf8

Write-Host "Report: $markdownPath" -ForegroundColor DarkGray
Write-Host "Report: $jsonPath" -ForegroundColor DarkGray
Write-Host ''

if ($failCount -gt 0) {
    Write-Host "Status: $overallStatus - fix FAIL items before starting labs" -ForegroundColor Red
    exit 1
} elseif ($warnCount -gt 0) {
    Write-Host "Status: $overallStatus - review WARN items" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "Status: $overallStatus - all checks passed" -ForegroundColor Green
    exit 0
}
