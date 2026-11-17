$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'neuroflex-dashboard-master\dist\neuroflex'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\NeuroFlex Dashboard'
$dataDir = Join-Path $env:LOCALAPPDATA 'NeuroFlex\data'
$exe = Join-Path $installDir 'neuroflex.exe'
$envFile = Join-Path $dataDir '.env'

if (-not (Test-Path -LiteralPath (Join-Path $source 'neuroflex.exe') -PathType Leaf)) {
    throw 'NeuroFlex desktop build is missing.'
}
if (Test-Path -LiteralPath $installDir) {
    throw "Installation directory already exists: $installDir"
}

New-Item -ItemType Directory -Path $installDir, $dataDir -Force | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $installDir -Recurse

$utf8 = New-Object System.Text.UTF8Encoding($false)
$config = if (Test-Path -LiteralPath $envFile) { [IO.File]::ReadAllText($envFile) } else { '' }
$settings = [ordered]@{
    NEUROFLEX_API_BASE_URL = 'https://i1eum0j7lf.execute-api.us-east-1.amazonaws.com/dev'
    COGNITO_REGION = 'us-east-1'
    COGNITO_CLIENT_ID = '65v6nki3fh1sgqbavlepf7gqkc'
}
if ($config -notmatch '(?m)^\s*(?:export\s+)?DJANGO_SECRET_KEY\s*=') {
    $settings['DJANGO_SECRET_KEY'] = 'change-me'
}
foreach ($key in $settings.Keys) {
    $assignment = "$key=$($settings[$key])"
    $pattern = '(?m)^[ \t]*(?:export[ \t]+)?' + [regex]::Escape($key) + '[ \t]*=[^\r\n]*'
    if ($config -match $pattern) {
        $config = [regex]::Replace($config, $pattern, $assignment)
    } else {
        if ($config -and -not $config.EndsWith("`n")) { $config += "`r`n" }
        $config += "$assignment`r`n"
    }
}
[IO.File]::WriteAllText($envFile, $config, $utf8)

$shell = New-Object -ComObject WScript.Shell
foreach ($folder in @([Environment]::GetFolderPath('DesktopDirectory'), [Environment]::GetFolderPath('Programs'))) {
    $shortcut = $shell.CreateShortcut((Join-Path $folder 'NeuroFlex Dashboard.lnk'))
    $shortcut.TargetPath = $exe
    $shortcut.WorkingDirectory = $installDir
    $shortcut.Save()
}

$process = Start-Process -FilePath $exe -WorkingDirectory $installDir -PassThru
Write-Output "Installed: $exe"
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Seconds 1
    $process.Refresh()
    if ($process.HasExited) { throw "NeuroFlex exited with code $($process.ExitCode)." }
    if ($process.MainWindowTitle -eq 'NeuroFlex Dashboard') {
        $login = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8000/login/' -TimeoutSec 5
        if ($login.StatusCode -eq 200 -and $login.Content -match 'Acceso \| NeuroFlex') {
            Write-Output 'Verified desktop window and login page.'
            exit 0
        }
    }
}
throw 'NeuroFlex desktop window could not be verified.'
