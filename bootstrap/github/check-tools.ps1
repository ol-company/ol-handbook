#Requires -Version 7.2
<#
.SYNOPSIS
    Kiểm tra công cụ cần cho Bước 1–5 của OL-Platform trên máy Windows.
.DESCRIPTION
    In bảng: tên công cụ, phiên bản tìm thấy, yêu cầu tối thiểu, trạng thái.
    Thoát với mã 1 nếu thiếu công cụ bắt buộc. Không cài đặt hay sửa gì trên máy.
.EXAMPLE
    pwsh -File .\bootstrap\github\check-tools.ps1
#>
[CmdletBinding()]
param()

# Dừng script ngay khi có lỗi PowerShell không được xử lý
$ErrorActionPreference = 'Stop'

# Danh sách kiểm tra: Name = tên hiển thị, Cmd = lệnh thực thi, VersionArgs = tham số in version,
# Pattern = regex lấy số version, Min = version tối thiểu, Required = bắt buộc ở Bước 1
$checks = @(
    @{ Name = 'Git';            Cmd = 'git';      VersionArgs = @('--version');  Pattern = '(\d+\.\d+\.\d+)'; Min = '2.40.0'; Required = $true  }
    @{ Name = 'GitHub CLI';     Cmd = 'gh';       VersionArgs = @('--version');  Pattern = '(\d+\.\d+\.\d+)'; Min = '2.60.0'; Required = $true  }
    @{ Name = 'Node.js';        Cmd = 'node';     VersionArgs = @('--version');  Pattern = '(\d+\.\d+\.\d+)'; Min = '26.0.0'; Required = $true  }
    @{ Name = 'pnpm';           Cmd = 'pnpm';     VersionArgs = @('--version');  Pattern = '(\d+\.\d+\.\d+)'; Min = '10.0.0'; Required = $true  }
    @{ Name = 'Lefthook';       Cmd = 'lefthook'; VersionArgs = @('version');    Pattern = '(\d+\.\d+\.\d+)'; Min = '1.10.0'; Required = $true  }
    @{ Name = 'Gitleaks';       Cmd = 'gitleaks'; VersionArgs = @('version');    Pattern = '(\d+\.\d+\.\d+)'; Min = '8.19.0'; Required = $true  }
    @{ Name = 'VS Code';        Cmd = 'code';     VersionArgs = @('--version');  Pattern = '(\d+\.\d+\.\d+)'; Min = '1.90.0'; Required = $false }
)

# Hàm so sánh version dạng a.b.c; trả về $true nếu $Found >= $Min
function Test-MinVersion([string]$Found, [string]$Min) {
    return ([version]$Found) -ge ([version]$Min)
}

$results = foreach ($c in $checks) {
    # Tìm lệnh trong PATH; -ErrorAction SilentlyContinue để không văng lỗi khi thiếu
    $exe = Get-Command $c.Cmd -ErrorAction SilentlyContinue
    if (-not $exe) {
        [pscustomobject]@{ Tool = $c.Name; Found = '-'; Min = $c.Min; Status = if ($c.Required) { 'THIẾU' } else { 'thiếu (tùy chọn)' } }
        continue
    }
    # Chạy lệnh lấy version, gộp stdout/stderr, lấy dòng đầu tiên khớp regex
    $raw = (& $c.Cmd @($c.VersionArgs) 2>&1 | Out-String)
    $m = [regex]::Match($raw, $c.Pattern)
    $ver = if ($m.Success) { $m.Groups[1].Value } else { 'không đọc được' }
    $ok = $m.Success -and (Test-MinVersion $ver $c.Min)
    [pscustomobject]@{ Tool = $c.Name; Found = $ver; Min = $c.Min; Status = if ($ok) { 'OK' } elseif ($c.Required) { 'CẦN NÂNG CẤP' } else { 'nên nâng cấp' } }
}

# --- Docker: có thể nằm trên Windows (Docker Desktop) hoặc chỉ trong WSL (Docker Engine) ---
$dockerMode = 'không tìm thấy'
$dockerVer = '-'
if (Get-Command docker -ErrorAction SilentlyContinue) {
    # Docker CLI có trên Windows → thường là Docker Desktop
    $v = (docker version --format '{{.Server.Version}}' 2>$null)
    if ($LASTEXITCODE -eq 0 -and $v) { $dockerMode = 'Windows CLI (Docker Desktop hoặc context tới WSL)'; $dockerVer = $v.Trim() }
}
if ($dockerVer -eq '-' -and (Get-Command wsl -ErrorAction SilentlyContinue)) {
    # Thử gọi docker bên trong distro WSL mặc định
    $v = (wsl -e docker version --format '{{.Server.Version}}' 2>$null)
    if ($LASTEXITCODE -eq 0 -and $v) { $dockerMode = 'Chỉ trong WSL (gọi qua: wsl -e docker ...)'; $dockerVer = ($v | Out-String).Trim() }
}
$results += [pscustomobject]@{ Tool = "Docker Engine [$dockerMode]"; Found = $dockerVer; Min = '27.0.0'; Status = if ($dockerVer -ne '-' -and (Test-MinVersion ($dockerVer -replace '[^\d\.].*$', '') '27.0.0')) { 'OK' } else { 'KIỂM TRA LẠI' } }

# In bảng kết quả
$results | Format-Table -AutoSize

# --- Kiểm tra cấu hình Git quan trọng ---
Write-Host "`nCấu hình Git:" -ForegroundColor Cyan
foreach ($key in 'user.name', 'user.email', 'gpg.format', 'user.signingkey', 'commit.gpgsign', 'core.autocrlf', 'init.defaultBranch') {
    $val = (git config --global --get $key 2>$null)
    '{0,-20} {1}' -f $key, ($(if ($val) { $val } else { '(chưa đặt)' }))
}

# --- Kiểm tra đăng nhập GitHub CLI (không in token) ---
Write-Host "`nGitHub CLI:" -ForegroundColor Cyan
gh auth status 2>&1 | Select-String -Pattern 'Logged in|scopes|Token:' | ForEach-Object { $_.Line.Trim() }

# Thoát mã 1 nếu thiếu công cụ bắt buộc → dùng được trong script khác
if ($results | Where-Object { $_.Status -in 'THIẾU', 'CẦN NÂNG CẤP' }) {
    Write-Host "`nCòn công cụ bắt buộc chưa đạt. Xem docs/01-cong-cu-va-github.md mục 1.2." -ForegroundColor Yellow
    exit 1
}
Write-Host "`nTất cả công cụ bắt buộc đã sẵn sàng." -ForegroundColor Green
