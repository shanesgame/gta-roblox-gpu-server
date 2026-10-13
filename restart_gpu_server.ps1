# One serve.py on port 8765 (required for real webpage screenshots)
Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue |
	Select-Object -ExpandProperty OwningProcess -Unique |
	ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1
# The capture browser (headless Edge) outlives a killed serve.py and keeps gigabytes of RAM; remove leftovers
Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" |
	Where-Object { $_.CommandLine -match 'playwright_chromiumdev_profile|\\\.capture-profile' } |
	ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Set-Location $PSScriptRoot
$py = "C:\Users\shane\AppData\Local\Programs\Python\Python310\python.exe"
if (-not (Test-Path $py)) { $py = "python" }
# Console window stays open (closing it stops the stream); a copy of the output goes to serve.log for diagnostics
$cmd = "& '$py' -X faulthandler -u serve.py 2>&1 | Tee-Object -FilePath '$PSScriptRoot\serve.log'; Write-Host 'serve.py exited with code' `$LASTEXITCODE; Read-Host 'press Enter to close'"
Start-Process -FilePath powershell -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cmd -WorkingDirectory $PSScriptRoot
Write-Host "serve.py started on http://127.0.0.1:8765/ (log: serve.log)"
