#Requires -Version 7.2
<#
.SYNOPSIS
    Khởi tạo GitHub Organization cho OL-Platform: cài đặt org, Actions policy, teams, repos,
    quyền team, CODEOWNERS, rulesets và Environments.

.DESCRIPTION
    Script chạy lại được nhiều lần (idempotent): thứ đã tồn tại thì bỏ qua hoặc cập nhật.
    Mọi cấu hình đọc từ thư mục config/ — sửa JSON thay vì sửa script.
    Không đọc, in hay yêu cầu bất kỳ token/mật khẩu nào; xác thực dùng phiên `gh auth login` sẵn có.

.PARAMETER Org
    Tên GitHub Organization đã tạo trên web (ví dụ: ol-platform-phuong).

.PARAMETER Visibility
    public (mặc định, đề xuất) hoặc private. Ảnh hưởng tới tính năng khả dụng theo gói GitHub.

.PARAMETER RequiredApprovals
    Số approve bắt buộc khi merge vào main. 0 khi làm một mình (không ai approve được PR của chính mình);
    đặt 1 khi có thêm người.

.PARAMETER RequireCodeOwnerReview
    Bắt buộc code owner approve. Chỉ bật khi team có ít nhất 2 người.

.PARAMETER DryRun
    Chỉ in các lệnh thay đổi sẽ chạy; các lệnh đọc (GET) vẫn chạy để kiểm tra trạng thái hiện tại.

.EXAMPLE
    pwsh -File .\bootstrap\github\bootstrap-github.ps1 -Org ol-platform-phuong -DryRun
    pwsh -File .\bootstrap\github\bootstrap-github.ps1 -Org ol-platform-phuong
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]{0,38}$')][string]$Org,
    [ValidateSet('public', 'private')][string]$Visibility = 'public',
    [ValidateRange(0, 6)][int]$RequiredApprovals = 0,
    [switch]$RequireCodeOwnerReview,
    [switch]$DryRun
)

# ---------------------------------------------------------------------------
# 0. Thiết lập chung
# ---------------------------------------------------------------------------
Set-StrictMode -Version Latest                      # Báo lỗi khi dùng biến chưa khai báo
$ErrorActionPreference = 'Stop'                     # Lỗi PowerShell → dừng script
$PSNativeCommandUseErrorActionPreference = $false   # Tự xử lý mã thoát của gh/git thay vì để PS ném lỗi

$ConfigDir   = Join-Path $PSScriptRoot 'config'                     # bootstrap/github/config
$HandbookDir = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path  # gốc repo ol-handbook
$script:Warnings = [System.Collections.Generic.List[string]]::new()   # Gom cảnh báo để in cuối

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "    [OK] $Text" -ForegroundColor Green }
function Write-Skip([string]$Text) { Write-Host "    [--] $Text" -ForegroundColor DarkGray }
function Add-Warning([string]$Text) { $script:Warnings.Add($Text); Write-Host "    [!!] $Text" -ForegroundColor Yellow }

# Gọi GitHub CLI.
#   -GhArgs   : danh sách tham số cho gh
#   -Body     : chuỗi JSON gửi qua stdin (dùng với `gh api ... --input -`)
#   -ReadOnly : lệnh chỉ đọc → vẫn chạy khi DryRun
#   -AllowFail: lỗi thì trả $null thay vì dừng script
function Invoke-Gh {
    param(
        [Parameter(Mandatory)][string[]]$GhArgs,
        [string]$Body,
        [switch]$ReadOnly,
        [switch]$AllowFail
    )
    $display = 'gh ' + ($GhArgs -join ' ')
    if ($DryRun -and -not $ReadOnly) {
        Write-Host "    [dry-run] $display" -ForegroundColor DarkGray
        if ($Body) { Write-Host "              body: $Body" -ForegroundColor DarkGray }
        return $null
    }
    if ($Body) {
        $out = $Body | & gh @GhArgs --input - 2>&1
    } else {
        $out = & gh @GhArgs 2>&1
    }
    $text = ($out | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFail) { return $null }
        throw "Lệnh thất bại (exit $LASTEXITCODE): $display`n$text"
    }
    return $text
}

# Đọc file JSON trong config/
function Read-Config([string]$RelativePath) {
    return Get-Content -Raw -Encoding utf8 (Join-Path $ConfigDir $RelativePath) | ConvertFrom-Json -Depth 20
}

# Chuyển object PowerShell sang JSON gọn để gửi API
function ConvertTo-Body($Object) { return ($Object | ConvertTo-Json -Depth 20 -Compress) }

# Kiểm tra một endpoint GET có tồn tại (HTTP 200) không
function Test-GhResource([string]$Endpoint) {
    return $null -ne (Invoke-Gh -GhArgs @('api', $Endpoint, '--silent') -ReadOnly -AllowFail)
}

# Chờ repo vừa tạo (tạo từ template là bất đồng bộ) có nhánh main
function Wait-RepoReady([string]$Repo) {
    if ($DryRun) { return }
    for ($i = 1; $i -le 20; $i++) {
        if (Test-GhResource "repos/$Org/$Repo/branches/main") { return }
        Start-Sleep -Seconds 3
    }
    throw "Repo $Org/$Repo chưa có nhánh main sau 60 giây."
}

# ---------------------------------------------------------------------------
# 1. Kiểm tra điều kiện đầu vào
# ---------------------------------------------------------------------------
Write-Step 'Kiểm tra GitHub CLI và quyền trên Organization'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'Chưa cài GitHub CLI (gh).' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Chưa cài Git.' }

$login = Invoke-Gh -GhArgs @('api', 'user', '--jq', '.login') -ReadOnly -AllowFail
if (-not $login) { throw 'gh chưa đăng nhập. Chạy: gh auth login (xem docs/01 mục 1.5).' }
Write-Ok "Đăng nhập GitHub với tài khoản: $login"

$membership = Invoke-Gh -GhArgs @('api', "orgs/$Org/memberships/$login", '--jq', '.role + "/" + .state') -ReadOnly -AllowFail
if ($membership -ne 'admin/active') {
    throw "Tài khoản $login không phải owner đang hoạt động của org '$Org' (nhận được: '$membership'). Tạo org trên web trước (docs/01 mục 1.6) và kiểm tra token có scope admin:org."
}
Write-Ok "$login là owner của $Org"

$plan = Invoke-Gh -GhArgs @('api', "orgs/$Org", '--jq', '.plan.name // "unknown"') -ReadOnly -AllowFail
if (-not $plan) { $plan = 'unknown' }
Write-Ok "Gói GitHub: $plan · Visibility repo: $Visibility"

# Suy ra tính năng khả dụng (theo tài liệu GitHub tại 11/2026):
#  - Rulesets: public trên mọi gói; private cần Pro/Team/Enterprise
#  - Environments: public trên mọi gói; private cần Pro/Team/Enterprise
#  - Required reviewers cho environment: public trên mọi gói; private chỉ Enterprise
$isPublic = $Visibility -eq 'public'
$caps = @{
    Rulesets         = $isPublic -or ($plan -notin 'free', 'unknown')
    Environments     = $isPublic -or ($plan -notin 'free', 'unknown')
    EnvReviewers     = $isPublic -or ($plan -like '*enterprise*')
    SecretScanning   = $isPublic
}
foreach ($k in $caps.Keys) { if (-not $caps[$k]) { Add-Warning "Tính năng '$k' không khả dụng với $Visibility + gói $plan → sẽ bỏ qua." } }

# ---------------------------------------------------------------------------
# 2. Cài đặt cấp Organization
# ---------------------------------------------------------------------------
$orgCfg = Read-Config 'org-settings.json'

Write-Step 'Cài đặt quyền thành viên của Organization'
Invoke-Gh -GhArgs @('api', '-X', 'PATCH', "orgs/$Org") -Body (ConvertTo-Body $orgCfg.organization) | Out-Null
Write-Ok 'Quyền mặc định: read; thành viên không tự tạo repo'

Write-Step 'Chính sách GitHub Actions'
$actionsBody = ConvertTo-Body $orgCfg.actionsPermissions
$res = Invoke-Gh -GhArgs @('api', '-X', 'PUT', "orgs/$Org/actions/permissions") -Body $actionsBody -AllowFail
if ($null -eq $res -and -not $DryRun) {
    # Một số gói/phiên bản API có thể chưa nhận trường sha_pinning_required → thử lại không có nó
    $fallback = $orgCfg.actionsPermissions | Select-Object -Property * -ExcludeProperty sha_pinning_required
    Invoke-Gh -GhArgs @('api', '-X', 'PUT', "orgs/$Org/actions/permissions") -Body (ConvertTo-Body $fallback) | Out-Null
    Add-Warning 'API không nhận sha_pinning_required. Bật thủ công: Org Settings → Actions → General → "Require actions to be pinned to a full-length commit SHA" (nếu có).'
}
Invoke-Gh -GhArgs @('api', '-X', 'PUT', "orgs/$Org/actions/permissions/selected-actions") -Body (ConvertTo-Body $orgCfg.selectedActions) | Out-Null
Invoke-Gh -GhArgs @('api', '-X', 'PUT', "orgs/$Org/actions/permissions/workflow") -Body (ConvertTo-Body $orgCfg.workflowPermissions) | Out-Null
Write-Ok 'Chỉ cho phép action của GitHub, verified creator và danh sách chọn lọc; GITHUB_TOKEN mặc định chỉ đọc'

# ---------------------------------------------------------------------------
# 3. Teams
# ---------------------------------------------------------------------------
Write-Step 'Teams'
$teams = (Read-Config 'teams.json').teams
foreach ($t in $teams) {
    if (Test-GhResource "orgs/$Org/teams/$($t.name)") {
        Write-Skip "Team $($t.name) đã tồn tại"
    } else {
        $body = ConvertTo-Body @{ name = $t.name; description = $t.description; privacy = 'closed' }
        Invoke-Gh -GhArgs @('api', '-X', 'POST', "orgs/$Org/teams") -Body $body | Out-Null
        Write-Ok "Tạo team $($t.name)"
    }
    # Đảm bảo bạn là maintainer của team (chạy lại không sao)
    Invoke-Gh -GhArgs @('api', '-X', 'PUT', "orgs/$Org/teams/$($t.name)/memberships/$login") -Body (ConvertTo-Body @{ role = 'maintainer' }) | Out-Null
}

# ---------------------------------------------------------------------------
# 4. Repositories
# ---------------------------------------------------------------------------
$repoCfg = Read-Config 'repos.json'

# Tạo repo bằng cách đẩy nội dung một thư mục local (dùng cho .github, template, handbook)
function New-SeededRepo($R) {
    $src = Join-Path $HandbookDir $R.seed
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("ol-seed-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    # Sao chép mọi thứ trừ thư mục .git (nếu thư mục nguồn đã là repo Git)
    Get-ChildItem -LiteralPath $src -Force | Where-Object { $_.Name -ne '.git' } |
        Copy-Item -Destination $tmp -Recurse -Force
    Push-Location $tmp
    try {
        git init --quiet --initial-branch=main
        git add --all
        git commit --quiet -m 'chore: khởi tạo repo'
        if ($LASTEXITCODE -ne 0) { throw 'git commit thất bại — kiểm tra user.name/user.email và cấu hình ký commit.' }
        Invoke-Gh -GhArgs @('repo', 'create', "$Org/$($R.name)", "--$Visibility", '--description', $R.description, '--source', '.', '--remote', 'origin', '--push') | Out-Null
    } finally {
        Pop-Location
        Remove-Item -LiteralPath $tmp -Recurse -Force
    }
}

Write-Step 'Repositories'
foreach ($r in $repoCfg.repos) {
    if (Test-GhResource "repos/$Org/$($r.name)") {
        Write-Skip "Repo $($r.name) đã tồn tại"
        continue
    }
    if ($r.PSObject.Properties.Name -contains 'seed') {
        if ($DryRun) { Write-Host "    [dry-run] tạo $($r.name) từ thư mục $($r.seed)" -ForegroundColor DarkGray }
        else { New-SeededRepo $r }
    } elseif ($r.PSObject.Properties.Name -contains 'fromTemplate') {
        Invoke-Gh -GhArgs @('repo', 'create', "$Org/$($r.name)", "--$Visibility", '--template', "$Org/$($repoCfg.templateRepo)", '--description', $r.description) | Out-Null
    }
    Wait-RepoReady $r.name
    if ($r.PSObject.Properties.Name -contains 'isTemplate') {
        Invoke-Gh -GhArgs @('repo', 'edit', "$Org/$($r.name)", '--template') | Out-Null
    }
    Write-Ok "Tạo repo $($r.name)"
}

# ---------------------------------------------------------------------------
# 5. Cài đặt từng repo: merge, bảo mật, quyền team, CODEOWNERS
# ---------------------------------------------------------------------------
Write-Step 'Cài đặt từng repo'
$repoSettings = ConvertTo-Body $orgCfg.repository
foreach ($r in $repoCfg.repos) {
    $full = "$Org/$($r.name)"

    # 5.1 Chỉ cho squash merge, tự xóa nhánh sau merge, tắt wiki/projects
    Invoke-Gh -GhArgs @('api', '-X', 'PATCH', "repos/$full") -Body $repoSettings | Out-Null

    # 5.2 Dependabot alerts + security updates (miễn phí mọi gói)
    Invoke-Gh -GhArgs @('api', '-X', 'PUT', "repos/$full/vulnerability-alerts") -AllowFail | Out-Null
    Invoke-Gh -GhArgs @('api', '-X', 'PUT', "repos/$full/automated-security-fixes") -AllowFail | Out-Null

    # 5.3 Secret scanning + push protection + báo cáo lỗ hổng riêng tư (miễn phí cho repo public)
    if ($caps.SecretScanning) {
        $sec = ConvertTo-Body @{ security_and_analysis = @{
            secret_scanning                 = @{ status = 'enabled' }
            secret_scanning_push_protection = @{ status = 'enabled' }
        } }
        if ($null -eq (Invoke-Gh -GhArgs @('api', '-X', 'PATCH', "repos/$full") -Body $sec -AllowFail) -and -not $DryRun) {
            Add-Warning "$($r.name): không bật được secret scanning qua API — kiểm tra Settings → Code security."
        }
        Invoke-Gh -GhArgs @('api', '-X', 'PUT', "repos/$full/private-vulnerability-reporting") -AllowFail | Out-Null
    }

    # 5.4 Quyền của từng team trên repo (pull | triage | push | maintain | admin)
    foreach ($p in $r.teams.PSObject.Properties) {
        Invoke-Gh -GhArgs @('api', '-X', 'PUT', "orgs/$Org/teams/$($p.Name)/repos/$full") -Body (ConvertTo-Body @{ permission = $p.Value }) | Out-Null
    }

    # 5.5 CODEOWNERS — ghi qua Contents API, phải làm TRƯỚC khi bật ruleset (ruleset chặn push thẳng vào main)
    $lines = @('# Sinh tự động bởi ol-handbook/bootstrap/github/bootstrap-github.ps1 — sửa trong config/repos.json',
               '# Dòng khớp SAU CÙNG thắng. Owner phải có quyền ghi vào repo.') +
             ($r.codeowners | ForEach-Object { $_.Replace('{org}', $Org) })
    $content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))
    $sha = Invoke-Gh -GhArgs @('api', "repos/$full/contents/.github/CODEOWNERS", '--jq', '.sha') -ReadOnly -AllowFail
    $body = @{ message = 'chore: cập nhật CODEOWNERS'; content = $content; branch = 'main' }
    if ($sha) { $body.sha = $sha }
    $put = Invoke-Gh -GhArgs @('api', '-X', 'PUT', "repos/$full/contents/.github/CODEOWNERS") -Body (ConvertTo-Body $body) -AllowFail
    if ($null -eq $put -and -not $DryRun) {
        Add-Warning "$($r.name): không ghi được CODEOWNERS (có thể ruleset đã bật). Cập nhật qua Pull Request."
    }

    Write-Ok "Đã cấu hình $($r.name)"
}

# ---------------------------------------------------------------------------
# 6. Rulesets cho nhánh mặc định và tag phát hành
# ---------------------------------------------------------------------------
Write-Step 'Rulesets'
if (-not $caps.Rulesets) {
    Write-Skip 'Bỏ qua: rulesets không khả dụng cho cấu hình hiện tại'
} else {
    $branchRs = Read-Config 'rulesets/default-branch.json'
    $prRule = $branchRs.rules | Where-Object { $_.type -eq 'pull_request' }
    $prRule.parameters.required_approving_review_count = $RequiredApprovals
    $prRule.parameters.require_code_owner_review = [bool]$RequireCodeOwnerReview
    $tagRs = Read-Config 'rulesets/release-tags.json'

    foreach ($r in $repoCfg.repos) {
        $full = "$Org/$($r.name)"
        foreach ($rs in @($branchRs, $tagRs)) {
            $existingId = Invoke-Gh -GhArgs @('api', "repos/$full/rulesets", '--jq', ".[] | select(.name == `"$($rs.name)`") | .id") -ReadOnly -AllowFail
            $method = if ($existingId) { 'PUT' } else { 'POST' }
            $path   = if ($existingId) { "repos/$full/rulesets/$existingId" } else { "repos/$full/rulesets" }
            $ok = Invoke-Gh -GhArgs @('api', '-X', $method, $path) -Body (ConvertTo-Body $rs) -AllowFail
            if ($null -eq $ok -and -not $DryRun -and $rs.target -eq 'branch') {
                # Fallback: API cũ có thể chưa nhận allowed_merge_methods (đã giới hạn bằng cài đặt repo ở 5.1)
                $copy = $rs | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
                $pr = $copy.rules | Where-Object { $_.type -eq 'pull_request' }
                $pr.parameters.PSObject.Properties.Remove('allowed_merge_methods')
                $ok = Invoke-Gh -GhArgs @('api', '-X', $method, $path) -Body (ConvertTo-Body $copy) -AllowFail
            }
            if ($null -eq $ok -and -not $DryRun) { Add-Warning "$($r.name): không áp dụng được ruleset '$($rs.name)'." }
        }
        Write-Ok "Ruleset cho $($r.name)"
    }
}

# ---------------------------------------------------------------------------
# 7. Environments cho repo triển khai (ol-infra)
# ---------------------------------------------------------------------------
Write-Step 'Environments'
$envCfg = Read-Config 'environments.json'
if (-not $caps.Environments) {
    Write-Skip 'Bỏ qua: Environments không khả dụng cho cấu hình hiện tại'
} else {
    $infra = "$Org/$($envCfg.repo)"
    foreach ($e in $envCfg.environments) {
        $body = @{
            wait_timer               = 0
            deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true }
        }
        if ($e.requireReviewers) {
            if ($caps.EnvReviewers) {
                $teamId = Invoke-Gh -GhArgs @('api', "orgs/$Org/teams/$($e.reviewerTeam)", '--jq', '.id') -ReadOnly -AllowFail
                if ($teamId) {
                    $body.reviewers = @(@{ type = 'Team'; id = [int64]$teamId })
                    # Làm một mình: không bật prevent_self_review, nếu không bạn không tự duyệt được
                    $body.prevent_self_review = $false
                }
            } else {
                Add-Warning "Environment $($e.name): không bật được required reviewers với $Visibility + gói $plan. Xem docs/01 mục 1.9 phương án thay thế."
            }
        }
        Invoke-Gh -GhArgs @('api', '-X', 'PUT', "repos/$infra/environments/$($e.name)") -Body (ConvertTo-Body $body) | Out-Null
        foreach ($b in $e.branches) {
            # 422/409 nếu policy đã tồn tại → bỏ qua
            Invoke-Gh -GhArgs @('api', '-X', 'POST', "repos/$infra/environments/$($e.name)/deployment-branch-policies") -Body (ConvertTo-Body @{ name = $b; type = 'branch' }) -AllowFail | Out-Null
        }
        Write-Ok "Environment $($e.name) (chỉ deploy từ: $($e.branches -join ', '))"
    }
}

# ---------------------------------------------------------------------------
# 8. Tổng kết
# ---------------------------------------------------------------------------
Write-Step 'Hoàn tất'
if ($DryRun) { Write-Host '    Chế độ DryRun: chưa thay đổi gì trên GitHub.' -ForegroundColor Yellow }
if ($script:Warnings.Count -gt 0) {
    Write-Host "`nCảnh báo cần xử lý thủ công:" -ForegroundColor Yellow
    $script:Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
Write-Host "`nKiểm tra: gh repo list $Org --limit 50" -ForegroundColor Cyan
