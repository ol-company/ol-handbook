#Requires -Version 7.2
<#
.SYNOPSIS
    Thay các giá trị giữ chỗ (__ORG__, __DOMAIN__...) trong mọi repo OL-Platform bằng giá trị thật của bạn.
.DESCRIPTION
    Chạy MỘT lần sau khi giải nén source vào thư mục làm việc. Chỉ sửa file văn bản trong các repo ol-*;
    bỏ qua .git, node_modules, dist. In danh sách file đã đổi để bạn review trước khi commit.
    Các giá trị account AWS / bucket chỉ cần khi tới Bước 6 — để trống thì giữ nguyên chỗ giữ.
.EXAMPLE
    pwsh -File .\ol-handbook\bootstrap\replace-placeholders.ps1 -Workspace D:\Coding\DevOps\ol-platform `
      -Org ol-platform-phuong -Domain ol.example.com -AlertEmail you@example.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]{0,38}$')][string]$Org,   # Chữ thường: scope npm bắt buộc chữ thường
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9.-]+\.[a-z]{2,}$')][string]$Domain,
    [Parameter(Mandatory)][string]$AlertEmail,
    [string]$SharedAccountId,
    [string]$DevAccountId,
    [string]$StagingAccountId,
    [string]$ProdAccountId,
    [string]$OrgId,
    [string]$StateBucket
)
$ErrorActionPreference = 'Stop'

$map = [ordered]@{
    '__ORG__'                = $Org
    '__DOMAIN__'             = $Domain
    '__ALERT_EMAIL__'        = $AlertEmail
    '__SHARED_ACCOUNT_ID__'  = $SharedAccountId
    '__DEV_ACCOUNT_ID__'     = $DevAccountId
    '__STAGING_ACCOUNT_ID__' = $StagingAccountId
    '__PROD_ACCOUNT_ID__'    = $ProdAccountId
    '__ORG_ID__'             = $OrgId
    '__STATE_BUCKET__'       = $StateBucket
}

$textExt = '.ts', '.tsx', '.js', '.mjs', '.json', '.yml', '.yaml', '.md', '.tf', '.tfvars', '.hcl', '.env', '.example', '.sh', '.ps1', '.sql', '.npmrc', ''
$changed = 0
Get-ChildItem -Path $Workspace -Directory -Filter 'ol-*' | ForEach-Object {
    Get-ChildItem -Path $_.FullName -Recurse -File -Force |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|dist|\.terraform)[\\/]' -and $textExt -contains $_.Extension -and $_.Name -ne 'replace-placeholders.ps1' } |
        ForEach-Object {
            $content = [IO.File]::ReadAllText($_.FullName)
            $new = $content
            foreach ($k in $map.Keys) {
                if ($map[$k]) { $new = $new.Replace($k, $map[$k]) }   # Bỏ qua giá trị chưa cung cấp
            }
            if ($new -ne $content) {
                [IO.File]::WriteAllText($_.FullName, $new, [Text.UTF8Encoding]::new($false))   # UTF-8 không BOM
                Write-Host "đã sửa: $($_.FullName)"
                $changed++
            }
        }
}
Write-Host "`nĐã cập nhật $changed file." -ForegroundColor Green
$left = Get-ChildItem -Path $Workspace -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules)[\\/]' } |
    Select-String -Pattern '__[A-Z_]+__' -List | Select-Object -ExpandProperty Path -Unique
if ($left) {
    Write-Host 'Còn giá trị giữ chỗ (bình thường nếu chưa tới Bước 6):' -ForegroundColor Yellow
    $left | ForEach-Object { Write-Host "  $_" }
}
