Set-Location 'C:\Data2AI-Labs\data-platform'

$sp = Test-Path 'secrets\shared-sp.txt'
$pat = Test-Path 'secrets\snowflake_pat.txt'
Write-Output "Secrets: SP=$sp PAT=$pat"

$tf = Test-Path "$HOME\.data2ai\bin\terraform.exe"
$git = [bool](Get-Command git -ErrorAction SilentlyContinue)
$snow = [bool](Get-Command snow -ErrorAction SilentlyContinue)
Write-Output "Tools: TF=$tf GIT=$git SNOW=$snow"

$prefix = $args[0]
Write-Output "--- Running Learner-Login $prefix ---"
.\scripts\Learner-Login.ps1 -LearnerPrefix $prefix 2>&1
