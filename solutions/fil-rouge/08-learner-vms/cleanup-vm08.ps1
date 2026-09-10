Get-Process | Where-Object { $_.Name -like '*Git*' -or $_.Name -like '*winget*' } | Stop-Process -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\Windows\TEMP\GitInstaller.exe' -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\GitInstaller.exe" -Force -ErrorAction SilentlyContinue
Write-Output 'cleanup done'
