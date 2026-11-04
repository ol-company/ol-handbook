# Bước 8 — Dữ liệu và bảo mật

> Phiên bản: 0.1 · Ngày: 03/11/2026 · Trạng thái: **Cấu hình đã viết (Terraform, realm, SQL), CHƯA kiểm chứng trên AWS.** RPO/RTO dưới đây là **mục tiêu**; con số thật chỉ có sau diễn tập khôi phục đầu tiên.

## 8.0 Tổng quan

| Mục | Nội dung |
|---|---|
| **Mục tiêu** | Dữ liệu được sao lưu và khôi phục được trong thời gian cam kết; mọi bí mật có chủ, có nơi lưu, có quy trình xoay vòng; quyền tối thiểu được liệt kê; mọi thao tác quan trọng để lại dấu vết |
| **Đầu vào** | Bước 6 (môi trường chạy trên AWS) |
| **Nơi thao tác** | AWS Console/CLI, GitHub Actions (`restore-drill.yml`), PR vào `ol-infra` |
| **File** | `ol-infra/infrastructure/modules/platform/{rds,backup,secrets,iam,waf,alb}.tf`, `ol-infra/db/bootstrap.sql`, `ol-infra/keycloak/realm-ol.yaml`, `ol-infra/scripts/restore-drill.sh` |
| **Kết quả** | Diễn tập khôi phục đạt; bảng 8.4 và 8.5 được rà; CloudTrail tổ chức bật |

## 8.1 Dữ liệu có gì

| Database (một instance RDS PostgreSQL 17 / môi trường) | Chủ | Mức nhạy cảm | Ghi chú |
|---|---|---|---|
| `keycloak` | Keycloak | Cao: hash mật khẩu, khóa TOTP, phiên | Chỉ Keycloak truy cập |
| `iam` | ol-iam-service | Cao: người dùng, quyền, audit | `audit_events` append-only |
| `warehouse` | ol-warehouse-service | Trung bình: dữ liệu nghiệp vụ theo tenant | RLS `ENABLE + FORCE` |
| `bff` | ol-bff | Cao: token đã mã hóa AES-256-GCM | Mất DB này = mọi người đăng nhập lại; **không** cần khôi phục |

"Database per service" được hiện thực ở mức **database + role riêng trên cùng instance**: service A không có quyền `CONNECT` vào database của B (`db/bootstrap.sql`). Tách instance riêng khi một service cần cấu hình/khả năng mở rộng khác (thêm sau).

## 8.2 Khái niệm (5 câu)

#### PITR (point-in-time recovery) của RDS
- **Nghĩa là gì?** RDS chụp snapshot hằng ngày + lưu liên tục transaction log → khôi phục về bất kỳ giây nào trong khoảng giữ lại (thường trễ ≤ 5 phút so với hiện tại).
- **Dùng thế nào?** `backup_retention_period`: dev 1 ngày, staging 7, prod 14. Khôi phục luôn tạo **instance mới**: `aws rds restore-db-instance-to-point-in-time`.
- **Thay thế bằng gì?** `pg_dump` theo lịch; replica logic.
- **Lợi thế khi chọn?** Có sẵn, không viết script sao lưu, RPO vài phút.
- **Không dùng thì sao?** Xóa nhầm một bảng lúc 15:00 chỉ quay về được bản dump đêm qua.

#### AWS Backup
- **Nghĩa là gì?** Dịch vụ lập lịch sao lưu tập trung, giữ bản sao lâu hơn giới hạn 35 ngày của PITR.
- **Dùng thế nào?** Chỉ prod (`backup_plan_enabled = true`): hằng ngày giữ 35 ngày, hằng tháng giữ 365 ngày.
- **Thay thế bằng gì?** Snapshot thủ công; script sao chép snapshot.
- **Lợi thế khi chọn?** Đáp ứng yêu cầu lưu audit ≥ 1 năm; có báo cáo tuân thủ.
- **Không dùng thì sao?** Không khôi phục được dữ liệu của 3 tháng trước khi cần điều tra.

#### Row-Level Security (RLS)
- **Nghĩa là gì?** PostgreSQL tự thêm điều kiện lọc vào mọi câu truy vấn theo policy.
- **Dùng thế nào?** Policy `tenant_id = nullif(current_setting('app.tenant_id', true), '')::uuid`; service đặt `set_config('app.tenant_id', $1, true)` trong transaction (`withTenant` ở node-kit). `FORCE` để cả chủ bảng cũng bị lọc. Chưa đặt tenant → không thấy dòng nào.
- **Thay thế bằng gì?** Chỉ thêm `WHERE tenant_id = ?` trong code; schema/database riêng mỗi tenant.
- **Lợi thế khi chọn?** Lớp phòng thủ thứ hai: quên `WHERE` vẫn không lộ dữ liệu tenant khác.
- **Không dùng thì sao?** Một truy vấn viết thiếu điều kiện là sự cố lộ dữ liệu giữa khách hàng.

#### Xoay vòng bí mật kiểu GitOps
- **Nghĩa là gì?** Đổi bí mật bằng một PR thay vì thao tác tay trong console.
- **Dùng thế nào?** `terraform.tfvars`: `secret_rotation = { "db/iam-app" = "2026-11-03" }`. Nhãn đổi → `random_password` sinh giá trị mới (`keepers`) → `deploy.sh` cập nhật Secrets Manager, `db-init` chạy `ALTER ROLE ... PASSWORD`, rồi biến `SECRETS_ROTATION` trong task definition đổi → ECS rolling để task nạp giá trị mới.
- **Thay thế bằng gì?** Secrets Manager rotation Lambda; đổi tay.
- **Lợi thế khi chọn?** Có review, có lịch sử, chạy lại được; không thêm Lambda.
- **Không dùng thì sao?** Bí mật không bao giờ được đổi vì "sợ hỏng".

---

## 8.3 Sao lưu và khôi phục

### Mục tiêu

| Môi trường | RPO (mất tối đa) | RTO (khôi phục trong) | Cơ chế |
|---|---|---|---|
| prod | ≤ 5 phút | ≤ 60 phút | PITR 14 ngày + AWS Backup 35 ngày/365 ngày + Multi-AZ (sự cố phần cứng: tự chuyển, ~1–2 phút) |
| staging | ≤ 24 giờ | Không cam kết | PITR 7 ngày |
| dev | Không cam kết | Không cam kết | PITR 1 ngày |

Bảo vệ thêm ở prod: `deletion_protection = true`, snapshot cuối khi xóa, secret có `recovery_window_in_days = 30`, state Terraform có versioning.

### Diễn tập (tự động, hằng tháng)

`ol-infra/.github/workflows/restore-drill.yml` chạy ngày 1 hằng tháng (09:00 giờ Việt Nam) hoặc chạy tay: khôi phục PITR sang instance **tạm**, chờ `available`, ghi thời gian khôi phục vào Summary của job, rồi xóa instance tạm. Không đụng instance đang chạy.

```powershell
gh workflow run restore-drill.yml -R <ORG>/ol-infra -f env=staging   # Chạy tay
gh run watch -R <ORG>/ol-infra                                       # Theo dõi
```

Kiểm tra dữ liệu bên trong bản khôi phục (đếm dòng, mở thử một tenant) là bước thủ công bổ sung mỗi quý — script hiện chỉ đo thời gian và trạng thái.

### Runbook khôi phục thật (prod)

> Chỉ thực hiện khi có sự cố được người phụ trách xác nhận. Ghi nhật ký từng bước vào issue sự cố.

1. **Dừng ghi**: đặt `desiredCount: 0` cho service bị ảnh hưởng qua PR khẩn (hoặc `aws ecs update-service --desired-count 0` rồi đưa vào Git ngay sau).
2. **Xác định thời điểm**: thời điểm ngay trước sự cố (UTC), từ audit log/CloudWatch.
3. **Khôi phục sang instance mới**:
   ```bash
   aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier ol-prod \
     --target-db-instance-identifier ol-prod-restored --restore-time 2026-11-03T07:59:00Z \
     --db-subnet-group-name <từ terraform output> --vpc-security-group-ids <db sg> \
     --db-parameter-group-name <của ol-prod> --multi-az --no-publicly-accessible --manage-master-user-password
   aws rds wait db-instance-available --db-instance-identifier ol-prod-restored
   ```
4. **Chọn cách đưa vào dùng:**
   - *Chỉ cần lấy lại một phần dữ liệu* (đa số trường hợp): kết nối instance khôi phục (qua task ECS tạm), `pg_dump` bảng/tenant cần thiết, nạp vào instance đang chạy. Xóa instance khôi phục.
   - *Thay toàn bộ*: đổi tên `ol-prod` → `ol-prod-old`, rồi `ol-prod-restored` → `ol-prod` (endpoint DNS giữ nguyên theo tên). Sau đó đồng bộ Terraform: `terraform state rm module.platform.aws_db_instance.this` và `terraform import module.platform.aws_db_instance.this ol-prod` (chạy qua workflow với role deploy). **[CHƯA XÁC MINH — diễn tập ở staging trước khi cần thật.]**
5. Bật lại service, chạy `smoke.sh`, kiểm tra nghiệp vụ, ghi postmortem (Bước 10).

## 8.4 Mã hóa

| Ở đâu | Lúc nghỉ | Lúc truyền |
|---|---|---|
| RDS | `storage_encrypted = true` (khóa AWS quản lý) | `rds.force_ssl = 1`; client xác minh chứng chỉ bằng CA bundle của RDS (`DB_SSL_CA_FILE`) |
| Secrets Manager | KMS (khóa AWS quản lý) | TLS |
| S3 state | SSE-S3, chặn public, versioning | Bucket policy bắt buộc TLS |
| ECR | AES-256 | TLS |
| Trình duyệt → ALB | — | TLS 1.2/1.3 (`ELBSecurityPolicy-TLS13-1-2-2021-06`), HTTP → 301 HTTPS, HSTS |
| ALB → task, task ↔ task | — | **HTTP trong VPC** (security group giới hạn nguồn). Rủi ro được chấp nhận ở giai đoạn này; nâng cấp: bật TLS của Service Connect hoặc mTLS khi có yêu cầu tuân thủ |
| Token trong phiên BFF | AES-256-GCM (`node:crypto`), khóa 32 byte trong Secrets Manager | — |

## 8.5 Quyền tối thiểu — bảng kiểm kê

| Chủ thể | Quyền | Giới hạn bởi | Cần thu hẹp sau |
|---|---|---|---|
| Bạn (SSO) | AdministratorAccess trên 4 account | MFA, phiên tạm thời | Tạo permission set `ReadOnly` dùng hằng ngày; Admin chỉ khi cần |
| `ol-gha-ecr-push` (shared) | Push vào `ol/*` | Trust: repo của org | — |
| `ol-gha-plan` (mỗi account) | ReadOnly + đọc state | Trust: `ol-infra`, PR/nhánh | — |
| `ol-gha-deploy` (mỗi account) | Quản trị hạ tầng | Trust: `ol-infra` + `environment:<env>` | Permission boundary chặn tạo IAM user/đổi Organizations |
| `ol-dns-records` (shared) | Ghi bản ghi trong zone | Trust: `ol-gha-*` của 3 account | — |
| ECS execution role | Kéo ECR, đọc đúng secret `ol/<env>/*`, ghi log | ARN cụ thể | — |
| ECS task role | Ghi X-Ray/CloudWatch (ADOT) | — | Tách role theo service khi service cần quyền AWS riêng |
| Role DB `*_app` | `SELECT/INSERT/UPDATE/DELETE` trên schema của mình; không DDL; `audit_events` không `UPDATE/DELETE`; `stock_movements` không `UPDATE/DELETE` | `bootstrap.sql` | — |
| Role DB `*_migrator` | DDL trên database của mình | Chỉ task migrate dùng | — |
| Client Keycloak `ol-bff` | Confidential, PKCE, redirect URI cố định | Realm | — |
| Client dịch vụ | Client credentials; IAM chỉ cấp `iam.authzChecker` cho danh sách `AUTHZ_CHECKER_SERVICES` | Catalog | — |
| GitHub App `ol-automation` | Theo từng job, giới hạn repo và quyền (`permission-*`) | Workflow | — |
| `GITHUB_TOKEN` mặc định | Chỉ đọc (cài đặt org) | Mỗi job khai báo `permissions:` | — |

Rà bảng này mỗi quý (Bước 10 — lịch bảo trì).

## 8.6 Bí mật: danh mục và xoay vòng

| Bí mật | Nơi lưu | Xoay vòng | Ảnh hưởng khi xoay |
|---|---|---|---|
| `db/*` (mật khẩu role DB) | Secrets Manager `ol/<env>/db/*` | `secret_rotation` + deploy | Vài giây lỗi kết nối mới cho tới khi task được thay |
| `clients/*` (client secret Keycloak) | `ol/<env>/clients/*` | `secret_rotation` + deploy (keycloak-config áp giá trị mới ở bước cuối) | Gọi service-to-service lỗi `503` trong vài phút giữa bước 4 và 5 của `deploy.sh` |
| `bff/session-key` | `ol/<env>/bff/session-key` | `secret_rotation` + deploy | **Mọi người phải đăng nhập lại** |
| `keycloak/admin` | `ol/<env>/keycloak/admin` | `secret_rotation` + deploy | Không |
| `ses/smtp` | Access key IAM user SES | `terraform apply -replace=...aws_iam_access_key.ses_smtp` qua workflow | Email lỗi vài phút |
| RDS master | Do RDS quản lý (`manage_master_user_password`) | RDS tự xoay (mặc định 7 ngày) | Không (service không dùng master; chỉ task `db-init` dùng và đọc giá trị mới mỗi lần chạy) |
| `OL_APP_PRIVATE_KEY` | GitHub org secret (Actions + Dependabot) | Tạo khóa mới trong cài đặt App → cập nhật 2 secret → xóa khóa cũ | Không |
| `DEPENDABOT_PACKAGES_TOKEN` | Dependabot org secret | Trước khi PAT hết hạn (90 ngày) | Dependabot không cập nhật được node-kit |
| `E2E_PASSWORD` | Environment secret | Đổi mật khẩu tài khoản kiểm thử + secret | Không |
| `.env` local | Máy bạn (không commit) | `./ol.ps1 reset` + xóa `.env` + `env` | Mất dữ liệu local |

Quy trình xoay vòng (ví dụ mật khẩu DB của iam-service ở staging):

```hcl
# ol-infra/infrastructure/envs/staging/terraform.tfvars — thêm hoặc sửa
secret_rotation = {
  "db/iam-app" = "2026-11-03"   # Nhãn bất kỳ; đổi nhãn = sinh bí mật mới
}
```

PR → `plan-staging` cho thấy `random_password.this["db/iam-app"]` must be replaced + task definition đổi → merge → `deploy.yml`. Kiểm chứng: `smoke.sh` đạt; log iam-service không còn lỗi xác thực DB sau khi rolling xong.

**Khi nghi bị lộ:** xoay vòng ngay theo cách trên (prod cần duyệt như mọi deploy); với khóa GitHub App/PAT: thu hồi trước, tạo mới sau.

## 8.7 Dấu vết kiểm toán

| Nguồn | Ghi gì | Giữ bao lâu | Xem ở đâu |
|---|---|---|---|
| IAM `audit_events` | Mọi thay đổi người dùng/nhóm/role/binding/tenant, bootstrap admin; người thực hiện, request id, IP | Vĩnh viễn trong DB + bản sao AWS Backup 365 ngày | Trang Audit của admin; API |
| Keycloak events | Đăng nhập (thành công/thất bại), đổi mật khẩu, TOTP; admin events | 30 ngày trong DB Keycloak; log container theo `log_retention_days` | Console Keycloak (chỉ qua mạng được phép); CloudWatch Logs |
| CloudTrail | Mọi lời gọi API AWS (ai đổi security group, ai đọc secret) | Theo cấu hình trail | Xem dưới |
| GitHub audit log | Thay đổi org, repo, ruleset, secret, deployment approval | Theo gói GitHub | Org → Settings → Audit log |
| Git history `ol-infra` | Ai thay đổi hạ tầng/triển khai gì | Vĩnh viễn | Git |

**Việc cần làm ngay (chưa có trong Terraform): CloudTrail cho cả tổ chức.** Đăng nhập account **management** → CloudTrail → **Create trail** → bật *Enable for all accounts in my organization*, lưu vào bucket S3 mới (bật mã hóa, versioning), bật *Log file validation*. Trail quản lý đầu tiên cho management events không tính phí; S3 tính phí lưu trữ [CHƯA XÁC MINH — kiểm tra trang giá CloudTrail]. Cân nhắc thêm GuardDuty (có phí theo khối lượng) khi có dữ liệu khách hàng thật.

## 8.8 Bảo mật ứng dụng — đã có gì

| Kiểm soát | Ở đâu |
|---|---|
| Header bảo mật (CSP, HSTS, X-Content-Type-Options, frame-ancestors) | `helmet` ở BFF/service; `security-headers.conf` ở nginx |
| CSRF | Header `X-OL-CSRF` + kiểm `Origin` ở BFF, cookie `SameSite=Lax` |
| Rate limit | `express-rate-limit` ở BFF (`/auth/*`, `/api/*`); WAF rate-based rule (staging/prod); Keycloak brute-force protection |
| Kiểm tra đầu vào | Zod ở mọi route (`SecureRouter.handle`) |
| Chính sách mật khẩu | Realm: ≥ 12 ký tự, không trùng username/email, lịch sử 5 |
| Phiên | Access token 5 phút, SSO idle 30 phút, tối đa 8 giờ |
| Lỗi không lộ chi tiết | `problem+json`, stack trace chỉ trong log |
| Log không chứa bí mật | `pino` redact `authorization`, `cookie`, `password`, `token`… |
| Admin Keycloak không lộ ra Internet | ALB trả 403 cho `/admin` và realm `master` (trừ `keycloak_admin_cidrs`) |
| Chuỗi cung ứng | Pin SHA action, lockfile, Dependabot, dependency review, Trivy, CodeQL, provenance |

## 8.9 Vá lỗi định kỳ

| Thành phần | Nguồn cập nhật | Tần suất |
|---|---|---|
| Dependency npm | Dependabot (thứ Hai) | Hằng tuần; bản vá bảo mật: ngay |
| Base image Node/nginx | Dependabot docker ở `ol-build-tooling` + đổi `BUILD_ARG_*_IMAGE` trong build-config | Hằng tháng |
| Keycloak | Chỉ bản mới nhất được vá → nâng patch trong `build-config/*/keycloak.env` | Hằng tháng; đọc release notes trước khi nâng minor |
| PostgreSQL | RDS minor version tự động trong cửa sổ bảo trì (`auto_minor_version_upgrade`) | Theo AWS |
| Node.js | Theo lịch LTS (Node 26 Active LTS tới 10/2027, bảo trì tới 4/2029 [CHƯA XÁC MINH ngày chính xác]) | Lên kế hoạch nâng major mỗi năm |
| Terraform provider | Dependabot terraform ở `ol-infra` | Hằng tuần |

## 8.10 Kiểm chứng (bạn chạy)

| # | Thử | Kết quả đúng |
|---|---|---|
| 1 | `restore-drill.yml` cho staging | Thành công; Summary ghi thời gian khôi phục |
| 2 | Xoay vòng `db/warehouse-app` ở dev | Deploy xanh, smoke đạt, không cần thao tác tay |
| 3 | `psql` bằng role `warehouse_app` (task tạm) chạy `UPDATE stock_movements ...` | `permission denied` |
| 4 | Kết nối RDS không TLS | Bị từ chối |
| 5 | `curl https://id.dev.<domain>/admin/` từ Internet | `403` |
| 6 | Tìm chuỗi bí mật trong image: `docker history`/Trivy secret scan | Không có |
| 7 | CloudTrail: đọc một secret bằng console | Sự kiện `GetSecretValue` xuất hiện trong Event history |

## 8.11 Hoàn tác

- Xoay vòng gây lỗi: revert PR `secret_rotation` **không** khôi phục giá trị cũ (đã bị thay); thay vào đó chạy lại `deploy.yml` để `db-init` và các task đồng bộ lại với giá trị hiện tại.
- Khôi phục nhầm: instance khôi phục là instance mới — xóa nó, không ảnh hưởng instance đang chạy.
- Secret xóa nhầm: `aws secretsmanager restore-secret --secret-id ol/<env>/...` trong thời gian chờ (7/30 ngày).
