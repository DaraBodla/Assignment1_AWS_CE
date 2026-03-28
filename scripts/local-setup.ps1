# ===========================================================================
# UniEvent — Local Development Setup (Windows PowerShell)
# Run this on your Windows PC to test the app before AWS deployment.
# ===========================================================================

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  UniEvent — Local Development Setup  " -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Check Python
try {
    $pyVersion = python --version 2>&1
    Write-Host "[OK] $pyVersion" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Python not found." -ForegroundColor Red
    Write-Host "Install Python from https://www.python.org/downloads/" -ForegroundColor Yellow
    Write-Host "IMPORTANT: Check 'Add Python to PATH' during installation." -ForegroundColor Yellow
    exit 1
}

# Navigate to app directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$appDir = Join-Path (Split-Path -Parent $scriptDir) "app"
Set-Location $appDir
Write-Host "[OK] Working directory: $appDir" -ForegroundColor Green

# Create virtual environment
if (-not (Test-Path "venv")) {
    Write-Host "-> Creating virtual environment..." -ForegroundColor Yellow
    python -m venv venv
}

Write-Host "-> Activating virtual environment..." -ForegroundColor Yellow
& .\venv\Scripts\Activate.ps1

Write-Host "-> Installing dependencies..." -ForegroundColor Yellow
pip install -r requirements.txt --quiet

# Check for .env
if (-not (Test-Path ".env")) {
    Write-Host ""
    Write-Host "[WARNING] No .env file found. Creating from template..." -ForegroundColor Yellow
    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
    } else {
        @"
FLASK_SECRET_KEY=local-dev-secret-change-me
TICKETMASTER_API_KEY=YOUR_KEY_HERE
S3_BUCKET_NAME=unievent-local-test
AWS_REGION=us-east-1
FETCH_INTERVAL=1800
"@ | Out-File -FilePath ".env" -Encoding UTF8
    }
    Write-Host "   Edit app\.env with your Ticketmaster API key before running." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[OK] Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  To run the app:" -ForegroundColor Cyan
Write-Host "    cd app" -ForegroundColor White
Write-Host "    .\venv\Scripts\Activate.ps1" -ForegroundColor White
Write-Host "    python app.py" -ForegroundColor White
Write-Host ""
Write-Host "  Then open http://localhost:5000 in your browser." -ForegroundColor Cyan
Write-Host ""
Write-Host "  Note: S3 uploads will not work locally unless you" -ForegroundColor Yellow
Write-Host "  have AWS credentials configured (aws configure)." -ForegroundColor Yellow
Write-Host ""

# Ask to run
$reply = Read-Host "Start the server now? [y/N]"
if ($reply -eq "y" -or $reply -eq "Y") {
    Write-Host "-> Starting UniEvent on http://localhost:5000 ..." -ForegroundColor Green
    python app.py
}
