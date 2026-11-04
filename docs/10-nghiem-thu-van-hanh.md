# Bước 10 — Nghiệm thu, vận hành và bảo trì

> Phiên bản: 0.1 · Ngày: 03/11/2026 · Trạng thái: **Danh mục và runbook đã viết. Chưa mục nào được nghiệm thu** — mỗi ô "Bằng chứng" phải được điền bằng link run/PR/ảnh chụp thật trước khi đánh dấu đạt.

## 10.0 Tổng quan

| Mục | Nội dung |
|---|---|
| **Mục tiêu** | Quyết định "được lên prod" dựa trên bằng chứng; có quy trình xử lý sự cố, runbook, lịch bảo trì, cách mở rộng hệ thống mà không phá chuẩn đã đặt |
| **Đầu vào** | Bước 1–9 |
| **Nơi thao tác** | Repo `ol-handbook` (tạo `docs/reports/`, `docs/runbooks/` khi điền), GitHub Issues |
| **Kết quả** | Bảng 10.1 điền đủ bằng chứng; buổi diễn tập sự cố đầu tiên có postmortem |

## 10.1 Danh mục sẵn sàng production

Cách dùng: sao chép bảng vào issue "Production readiness v1", điền cột Bằng chứng. Mục **Bắt buộc** chưa đạt = chưa lên prod.

### 1. Yêu cầu và thiết kế

| # | Tiêu chí | Mức | Bằng chứng |
|---|---|---|---|
| 1.1 | Kiến trúc, quyết định và NFR được ghi (Bước 0) và còn đúng với hệ thống thật | Bắt buộc | Link `00-kien-truc-va-quyet-dinh.md` + ngày rà |
| 1.2 | Ranh giới v1 rõ: IAM + warehouse + admin; module khác chưa làm | Bắt buộc | |
| 1.3 | Mô hình quyền (catalog) được chủ sản phẩm duyệt | Bắt buộc | |

### 2. Quy trình code

| # | Tiêu chí | Mức | Bằng chứng |
|---|---|---|---|
| 2.1 | Ruleset: không push thẳng `main`, chữ ký commit, squash, check bắt buộc | Bắt buộc | `gh api repos/<ORG>/<repo>/rulesets/<id>` |
| 2.2 | CODEOWNERS đúng team | Bắt buộc | |
| 2.3 | Action pin SHA; `GITHUB_TOKEN` chỉ đọc mặc định | Bắt buộc | Cài đặt org |
| 2.4 | Dependabot chạy và có người xử lý PR hằng tuần | Bắt buộc | |
| 2.5 | Review bắt buộc ≥ 1 người | Khi team ≥ 2 | |

### 3. Phát hành

| # | Tiêu chí | Mức | Bằng chứng |
|---|---|---|---|
| 3.1 | Image build bằng Dockerfile tập trung, có nhãn truy vết, triển khai bằng digest | Bắt buộc | `deploy/prod/*.yaml` + `docker inspect` |
| 3.2 | Attestation provenance được kiểm trước deploy | Bắt buộc | Log `verify-artifacts` |
| 3.3 | Cùng digest đi dev → staging → prod | Bắt buộc | So sánh `deploy/*/` |
| 3.4 | Rollback bằng revert PR đã diễn tập | Bắt buộc | Kịch bản 7.7 #5 |
| 3.5 | Circuit breaker đã diễn tập | Bắt buộc | 7.7 #6 |
| 3.6 | Migration theo expand/contract (checklist PR) | Bắt buộc | |

### 4. Hạ tầng

| # | Tiêu chí | Mức | Bằng chứng |
|---|---|---|---|
| 4.1 | Account riêng cho prod; SSO + MFA; không access key dài hạn | Bắt buộc | |
| 4.2 | Toàn bộ hạ tầng bằng Terraform; `drift.yml` không báo lệch | Bắt buộc | Run `drift` gần nhất |
| 4.3 | State có versioning, khóa, giới hạn quyền | Bắt buộc | |
| 4.4 | RDS Multi-AZ, deletion protection, task ≥ 2 trải 2 AZ | Bắt buộc | |
| 4.5 | TLS 1.2+, HTTP → HTTPS, chứng chỉ tự gia hạn | Bắt buộc | `smoke.sh` |
| 4.6 | NAT đơn — chấp nhận rủi ro mất đường ra Internet khi 1 AZ lỗi | Ghi nhận | |

### 5. Ứng dụng

| # | Tiêu chí | Mức | Bằng chứng |
|---|---|---|---|
| 5.1 | Health live/ready; graceful shutdown | Bắt buộc | |
| 5.2 | Timeout, retry có giới hạn, fail closed | Bắt buộc | Diễn tập 9.8 #1 |
| 5.3 | Lỗi theo problem+json, không lộ stack trace | Bắt buộc | |
| 5.4 | Cấu hình runtime tách khỏi image; không bí mật trong image/bundle | Bắt buộc | 8.10 #6 |

### 6. Dữ liệu

| # | Tiêu chí | Mức | Bằng chứng |
|---|---|---|---|
| 6.1 | PITR 14 ngày + AWS Backup | Bắt buộc | |
| 6.2 | Diễn tập khôi phục đạt, RTO đo được ≤ mục tiêu | Bắt buộc | Run `restore-drill` |
| 6.3 | Database/role riêng mỗi service; RLS cho dữ liệu nghiệp vụ | Bắt buộc | Test RLS |
| 6.4 | Audit append-only, giữ ≥ 1 năm | Bắt buộc | |

### 7. Bảo mật

| # | Tiêu chí | Mức | Bằng chứng |
|---|---|---|---|
| 7.1 | Kịch bản IAM 3.6 đạt (thiếu quyền, cross-tenant, MFA admin, thu hồi) | Bắt buộc | |
| 7.2 | Không có lỗ hổng CRITICAL/HIGH đã có bản vá chưa xử lý | Bắt buộc | Tab Security |
| 7.3 | Admin Keycloak không truy cập được từ Internet | Bắt buộc | `smoke.sh` |
| 7.4 | Bảng quyền tối thiểu 8.5 đã rà | Bắt buộc | |
| 7.5 | CloudTrail tổ chức bật | Bắt buộc | |
| 7.6 | SES production access (nếu gửi email cho người ngoài) | Bắt buộc khi có khách | |
| 7.7 | Kiểm thử xâm nhập độc lập | Nên có trước khách hàng đầu tiên | |

### 8. Quan sát

| # | Tiêu chí | Mức | Bằng chứng |
|---|---|---|---|
| 8.1 | Log JSON có request id; tra được một request end-to-end | Bắt buộc | |
| 8.2 | Alarm SLO + hạ tầng gửi tới người thật (đã thử) | Bắt buộc | 9.3 |
| 8.3 | Dashboard | Bắt buộc | |
| 8.4 | Trace trong X-Ray | Nên có | |

### 9. Độ tin cậy

| # | Tiêu chí | Mức | Bằng chứng |
|---|---|---|---|
| 9.1 | Load test đạt NFR ở staging | Bắt buộc | Báo cáo k6 |
| 9.2 | Diễn tập lỗi 9.8 đạt | Bắt buộc | |
| 9.3 | Autoscaling hoạt động | Bắt buộc | Dashboard trong load test |

### 10. Vận hành và chi phí

| # | Tiêu chí | Mức | Bằng chứng |
|---|---|---|---|
| 10.1 | Runbook 10.3 có người đọc thử | Bắt buộc | |
| 10.2 | Có người nhận cảnh báo và thời gian phản hồi được thống nhất | Bắt buộc | |
| 10.3 | Budgets + cảnh báo chi phí | Bắt buộc | |
| 10.4 | Ít nhất 2 người có quyền quản trị (tránh phụ thuộc một người) | Bắt buộc trước khách hàng | |
| 10.5 | Tài liệu onboarding được người mới làm theo thành công | Nên có | |

## 10.2 Quy trình sự cố

| Mức | Định nghĩa | Phản hồi |
|---|---|---|
| SEV1 | Prod không dùng được, lộ dữ liệu, mất dữ liệu | Ngay; mọi việc khác dừng |
| SEV2 | Một chức năng chính lỗi / chậm nghiêm trọng (fast burn) | Trong giờ làm việc: ≤ 30 phút |
| SEV3 | Lỗi nhỏ, có cách tránh (slow burn) | Ngày làm việc kế tiếp |

Các bước:
1. **Ghi nhận**: mở issue `incident: <mô tả>` trong `ol-handbook` (nhãn `incident`, `sev1/2/3`), ghi thời điểm phát hiện.
2. **Giảm thiểu trước, tìm nguyên nhân sau**: rollback (revert PR digest), scale, tắt chức năng.
3. **Cập nhật** issue mỗi 30 phút với SEV1/2.
4. **Đóng** khi đã hết ảnh hưởng; SEV1/2 phải có postmortem trong 5 ngày làm việc.

### Mẫu postmortem (không đổ lỗi)

```markdown
# Postmortem: <tiêu đề> — <ngày>
- Mức: SEV? · Thời gian ảnh hưởng: <từ> → <đến> (UTC+7) · Người viết: <tên>
## Tóm tắt (3 câu)
## Ảnh hưởng (người dùng/tenant nào, bao nhiêu request lỗi, ngân sách lỗi tiêu tốn)
## Dòng thời gian (phát hiện, giảm thiểu, khắc phục)
## Nguyên nhân gốc (5 lần "tại sao")
## Điều gì hiệu quả / chưa hiệu quả
## Hành động (mỗi mục: chủ, hạn, link issue)
```

## 10.3 Runbook

Mỗi runbook: triệu chứng → kiểm tra → xử lý → xác nhận. Lệnh dùng profile SSO của môi trường (`$env:AWS_PROFILE = 'ol-prod-admin'`; thao tác thay đổi trên prod ưu tiên qua PR).

**RB-01 Tỉ lệ lỗi cao (SLO burn)**
1. Dashboard: lỗi ở ELB (`HTTPCode_ELB_5XX`: không có target khỏe) hay ở Target (ứng dụng trả 5xx)?
2. Có deploy trong 1 giờ qua? (`gh run list -R <ORG>/ol-infra -w deploy -L 5`) → có: revert PR digest gần nhất.
3. Logs Insights truy vấn #1 (Bước 9.2) → route và service nào; truy vấn #5 → IAM có fail closed không.
4. Phụ thuộc: RDS (RB-04), Keycloak, IAM (`aws ecs describe-services --cluster ol-prod --services iam-service --query 'services[0].{running:runningCount,desired:desiredCount,events:events[0:3]}'`).
5. Xác nhận: alarm về OK, smoke đạt.

**RB-02 Chậm (p95 cao)**
1. Truy vấn #3: route nào chậm. 2. CPU service > 80% → autoscaling đã chạm `maxCount`? tăng `maxCount` qua PR. 3. RDS CPU/kết nối cao → truy vấn chậm (Performance Insights → Top SQL) → thêm index (migration riêng, `CONCURRENTLY`). 4. Cache authorize trượt nhiều (log IAM tăng vọt) → kiểm `AUTHZ_CACHE_TTL_SECONDS`.

**RB-03 Target không khỏe / task khởi động lại liên tục**
1. `aws ecs describe-services` → `events`. 2. Log stream của task dừng: lỗi cấu hình (biến thiếu → Zod báo khi khởi động), không kết nối DB, không lấy được secret. 3. Mới deploy → circuit breaker đã rollback chưa? Nếu chưa, revert PR.

**RB-04 RDS quá tải / sắp đầy**
1. Storage: bật/tăng `max_allocated_storage` (autoscaling dung lượng) hoặc `allocated_storage` qua PR. 2. CPU: Top SQL; tạm giảm `maxCount` của service gây tải; nâng `rds_instance_class` qua PR (Multi-AZ: chuyển đổi có gián đoạn ngắn — làm trong cửa sổ bảo trì). 3. Kết nối: tổng `pool max × số task` vượt giới hạn → giảm pool hoặc thêm RDS Proxy (thêm sau).

**RB-05 Người dùng không đăng nhập được**
1. `https://id.<domain>/realms/ol/.well-known/openid-configuration` trả 200? 2. Keycloak task chạy? log có lỗi DB? 3. Một người: tài khoản bị khóa do brute-force → Keycloak admin (qua mạng cho phép) hoặc platform admin → "Đăng xuất mọi nơi/Reset MFA". 4. Mọi người, sau khi xoay `bff/session-key`: đúng thiết kế, đăng nhập lại.

**RB-06 Chi phí vượt dự báo**
1. Cost Explorer → nhóm theo dịch vụ, account. 2. Thủ phạm thường gặp: NAT data processing (tăng log/trace gửi ra ngoài?), CloudWatch Logs ingest (`LOG_LEVEL=debug` quên tắt), task không tắt ngoài giờ (kiểm scheduled actions), RDS dev không dừng. 3. Sửa qua PR.

**RB-07 Nghi lộ bí mật**
1. Thu hồi/xoay ngay (Bước 8.6). 2. CloudTrail: ai đã dùng bí mật/role trong khoảng thời gian liên quan. 3. GitHub: secret scanning alert, audit log. 4. SEV1 nếu có dấu hiệu truy cập dữ liệu → postmortem.

**RB-08 Khôi phục dữ liệu** — Bước 8.3 "Runbook khôi phục thật".

## 10.4 Lịch bảo trì

| Tần suất | Việc | Người |
|---|---|---|
| Hằng ngày | Xem email cảnh báo; `drift.yml` (08:00) không báo lệch | Trực |
| Hằng tuần (thứ Hai) | Xử lý PR Dependabot; xem tab Security các repo; xem ngân sách | platform + chủ repo |
| Hằng tháng | `restore-drill` (tự động ngày 1) — đọc kết quả; nâng patch Keycloak + base image; rà lỗ hổng tồn đọng | platform |
| Hằng quý | Rà bảng quyền 8.5 và thành viên team/org; xoay vòng bí mật `db/*`, `clients/*`; kiểm tra dữ liệu trong bản khôi phục; diễn tập lỗi 9.8; rà SLO và ngưỡng alarm; rà chi phí và rightsizing | platform + security |
| Hằng năm | Nâng Node LTS, PostgreSQL major (thử ở staging trước); rà kiến trúc Bước 0; kiểm thử xâm nhập | Cả đội |
| Trước hạn | PAT `DEPENDABOT_PACKAGES_TOKEN` (90 ngày); khóa GitHub App (theo chính sách) | platform |

## 10.5 Onboarding người mới

1. Thêm vào org + team phù hợp (bootstrap `teams.json` → chạy lại script hoặc web).
2. Người mới làm Bước 1 mục cài công cụ + SSH signing, Bước 2 mục chạy local; mục tiêu ngày đầu: `./ol.ps1 check` xanh và mở PR đầu tiên (sửa tài liệu này nếu có chỗ sai).
3. Quyền AWS: chỉ cấp permission set ReadOnly cho dev/staging; prod chỉ khi cần và có lý do.
4. Đọc: Bước 0, Bước 3 (mô hình quyền), Bước 7 (đường phát hành), 10.2–10.3.
5. Bật "Require code owner review" và `-RequiredApprovals 1` trong bootstrap khi team ≥ 2.

Offboarding: gỡ khỏi org/team, gỡ gán Identity Center, xoay bí mật người đó từng có thể đọc (đặc biệt nếu từng có quyền admin), rà audit log.

## 10.6 Thêm một service mới (ví dụ `order-service`)

Mọi chuẩn đã có sẵn — thêm service là điền vào đúng chỗ:

| # | Việc | Nơi |
|---|---|---|
| 1 | Tạo repo `ol-order-service` từ template | `bootstrap/github/config/repos.json` → chạy lại bootstrap |
| 2 | Khung code: sao chép cấu trúc `ol-warehouse-service` (domain/application/infrastructure/interfaces, `SecureRouter`, `withTenant`, RLS) | Repo mới |
| 3 | Permission `order.*` + role hệ thống; thêm `ol-order-service` vào `AUTHZ_CHECKER_SERVICES` | `ol-iam-service/src/domain/catalog.ts` |
| 4 | Client Keycloak `ol-order-service` (client credentials, audience `ol-api`) | `ol-infra/keycloak/realm-ol.yaml` |
| 5 | Database + role `order_app`/`order_migrator` | `ol-infra/db/bootstrap.sql`, `local/compose*.yaml` |
| 6 | Secret `db/order-app`, `db/order-migrator`, `clients/ol-order-service` | `modules/platform/secrets.tf` |
| 7 | ECR repo | `envs/shared/main.tf` (`modules`) |
| 8 | Định nghĩa service + task migrate | `modules/platform/ecs.tf`, danh sách `modules` ở `envs/*/main.tf` |
| 9 | Build config + deploy YAML × 3 môi trường | `ol-infra/build-config/*/order-service.env`, `deploy/*/order-service.yaml` |
| 10 | Route BFF `/api/order/*` | `ol-bff/src/main.ts` (`upstreams`) + biến `ORDER_INTERNAL_URL` |
| 11 | CI | `.github/workflows/ci.yml` sao chép, đổi `module` |
| 12 | Check bắt buộc | `config/required-checks.json` → `set-required-checks.ps1` |
| 13 | Frontend: thư mục `src/features/orders/` (api/hooks/page) | `ol-web-admin` |
| 14 | Migration bước `deploy.sh` | Thêm vào vòng lặp migrate |

## 10.7 Khi nào thêm thành phần mới (đã có chủ đích chưa làm)

| Thành phần | Thêm khi | Gợi ý |
|---|---|---|
| Message broker / hàng đợi | Có luồng bất đồng bộ thật: webhook cho đối tác, sự kiện từ thiết bị IoT, xử lý đơn hàng nhiều bước | Amazon SQS/SNS hoặc EventBridge trước; Kafka/MSK chỉ khi cần replay/throughput lớn. Mẫu outbox trong DB của service |
| Cache (Redis) | Đo được truy vấn đọc lặp nặng mà index không giải quyết | ElastiCache Valkey; cache quyết định IAM đang ở bộ nhớ tiến trình là đủ |
| API cho đối tác | Có đối tác thật | Client credentials riêng mỗi đối tác (Keycloak), rate limit riêng, webhook ký HMAC bằng thư viện chuẩn, OpenAPI |
| Camera AI / robot / IoT | Có thiết bị | AWS IoT Core (MQTT, chứng chỉ thiết bị). Nhắc lại Bước 0: nền tảng chỉ **điều phối** (giao nhiệm vụ, nhận trạng thái); điều khiển thời gian thực và dừng an toàn nằm ở thiết bị/edge, không phụ thuộc mạng |
| Kubernetes | Hàng chục service, cần lịch GPU cho AI, hoặc đa cloud | EKS; đến lúc đó image/digest/GitOps hiện tại vẫn dùng lại được |
| Canary/blue-green | Lưu lượng đủ lớn, SLA chặt | Bước 7.2 |
| Đa region | Yêu cầu RTO khi mất cả region | Bản sao RDS cross-region, ECR replication |

## 10.8 Chi phí và năng lực

- Mỗi tháng: Cost Explorer theo account; so với ngân sách (Bước 6.11).
- Rightsizing hằng quý: CPU trung bình < 20% ở prod trong cả quý → giảm `cpu/memory` trong `deploy/prod/*.yaml`; RDS CPU < 20% → cân nhắc hạ class (giữ Multi-AZ).
- Năng lực: mỗi lần load test ghi lại "req/s mỗi task ở 60% CPU" → dùng để đặt `maxCount` và dự báo khi số tenant tăng.
- Savings Plans/Reserved Instances: chỉ cân nhắc sau 3 tháng có số liệu ổn định ở prod.

## 10.9 Hiện trạng kiểm chứng của bộ tài liệu này

| Hạng mục | Trạng thái |
|---|---|
| Kiến trúc, quyết định, mô hình quyền | Đã viết |
| Script bootstrap GitHub (Bước 1) | Đã viết, kiểm tra cú pháp JSON/YAML; **chưa chạy** với org thật |
| Hook commit (lefthook regex), `validate-build-config.sh` | Đã chạy thử trong môi trường soạn thảo — đạt |
| Toàn bộ mã TypeScript (node-kit, IAM, warehouse, BFF, web-admin) | **Chưa biên dịch, chưa chạy test** (môi trường soạn thảo không truy cập được npm) |
| Dockerfile, compose | **Chưa build** |
| Terraform | **Chưa `init/validate/plan`** |
| Workflow GitHub Actions | Kiểm tra cú pháp YAML; **chưa chạy** |
| Tag image/công cụ, ID winget, selector Keycloak, chi phí | **[CHƯA XÁC MINH]** — danh sách trong README |

Thứ tự đề xuất để bạn biến "đã viết" thành "đã kiểm chứng": Bước 1 → Bước 2 (đây là lúc code được biên dịch lần đầu — gửi lỗi về để sửa) → Bước 3 → Bước 5 → Bước 6 → Bước 7 → Bước 8–9 → điền bảng 10.1.
