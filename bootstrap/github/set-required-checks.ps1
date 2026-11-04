#Requires -Version 7.2
<#
.SYNOPSIS
    Thêm (hoặc cập nhật) luật "required status checks" vào ruleset default-branch-protection của từng repo.
.DESCRIPTION
    Chạy SAU KHI mỗi repo đã có ít nhất một PR chạy CI thành công (để tên check tồn tại và đã đối chiếu).
    Danh sách check đọc từ config/required-checks.json. Script chạy lại được nhiều lần.
    Không đọc hay in token; dùng phiên `gh auth login` sẵn có.
.PARAMETER Org
    Tên GitHub Organization.
.PARAMETER ActionsAppId
    ID của GitHub App "GitHub Actions" — ràng buộc check phải do Actions tạo (chống giả mạo bằng Status API).
    Xác minh: gh api repos/<org>/<repo>/commits/main/check-runs --jq '.check_runs[0].app.id'
.PARAMETER Only
    Chỉ áp dụng cho một repo (ví dụ ol-iam-service).
.PARAMETER DryRun
    Chỉ in ruleset sẽ gửi, không thay đổi.
.EXAMPLE
    pwsh -File .\bootstrap\github\set-required-checks.ps1 -Org ol-platform-phuong -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Org,
    [int]$ActionsAppId = 15368,
    [string]$Only,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$cfg = Get-Content (Join-Path $PSScriptRoot 'config/required-checks.json') -Raw | ConvertFrom-Json -AsHashtable

foreach ($repo in $cfg.repos.Keys) {
    if ($Only -and $repo -ne $Only) { continue }
    $full = "$Org/$repo"
    # Tìm ruleset do bootstrap-github.ps1 tạo
    $id = gh api "repos/$full/rulesets" --jq '.[] | select(.name == "default-branch-protection") | .id'
    if (-not $id) { Write-Host "[!!] ${repo}: chưa có ruleset default-branch-protection — chạy bootstrap-github.ps1 trước" -ForegroundColor Yellow; continue }

    # Lấy ruleset hiện tại, bỏ luật required_status_checks cũ (nếu có), thêm luật mới
    $rs = gh api "repos/$full/rulesets/$id" | ConvertFrom-Json -AsHashtable
    $rules = @($rs.rules | Where-Object { $_.type -ne 'required_status_checks' })
    $rules += @{
        type       = 'required_status_checks'
        parameters = @{
            strict_required_status_checks_policy = $false   # Không bắt rebase nhánh mỗi khi main đổi (squash + check lại khi merge là đủ cho team nhỏ)
            do_not_enforce_on_create             = $false
            required_status_checks               = @($cfg.repos[$repo] | ForEach-Object { @{ context = $_; integration_id = $ActionsAppId } })
        }
    }
    $body = @{
        name          = $rs.name
        target        = $rs.target
        enforcement   = $rs.enforcement
        bypass_actors = @($rs.bypass_actors)
        conditions    = $rs.conditions
        rules         = $rules
    } | ConvertTo-Json -Depth 20 -Compress

    if ($DryRun) { Write-Host "[dry] $repo ← $($cfg.repos[$repo] -join ', ')"; continue }
    $body | gh api -X PUT "repos/$full/rulesets/$id" --input - | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Cập nhật ruleset $repo thất bại" }
    Write-Host "[OK] ${repo}: $($cfg.repos[$repo].Count) check bắt buộc" -ForegroundColor Green
}
