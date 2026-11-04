# Bước 9 — Quan sát và độ tin cậy

> Phiên bản: 0.1 · Ngày: 03/11/2026 · Trạng thái: **Cấu hình đã viết (log JSON, OpenTelemetry, alarm, dashboard, k6), CHƯA chạy trên AWS.** Ngưỡng SLO là mục tiêu ban đầu, điều chỉnh sau 2–4 tuần có số liệu thật.

## 9.0 Tổng quan

| Mục | Nội dung |
|---|---|
| **Mục tiêu** | Khi có sự cố: biết trong vài phút (cảnh báo), tìm ra request lỗi trong vài phút (log + trace theo request id), hiểu ảnh hưởng (SLO); hệ thống chịu được lỗi phụ thuộc theo cách đã thiết kế |
| **Đầu vào** | Bước 6–8 |
| **Nơi thao tác** | CloudWatch (Logs Insights, Metrics, Alarms, Dashboards), X-Ray; local: Grafana `https://grafana.ol.test` |
| **File** | `ol-node-kit/src/{logger,otel/register,http/middleware,http/server,authz/authorizer}.ts`, `ol-infra/infrastructure/modules/platform/monitoring.tf`, `ol-infra/infrastructure/modules/ecs-service/main.tf` (ADOT), `ol-infra/loadtest/warehouse.js` |
| **Kết quả** | Đã nhận email cảnh báo thử; tra được một request từ log sang trace; load test đạt ngưỡng; 3 bài diễn tập lỗi đạt |

## 9.1 Khái niệm (5 câu)

#### Ba tín hiệu: log, metric, trace
- **Nghĩa là gì?** Log = sự kiện chi tiết (một dòng JSON mỗi request/lỗi); metric = con số theo thời gian (số request, tỉ lệ lỗi, p95); trace = đường đi của một request qua nhiều service.
- **Dùng thế nào?** Log: pino → stdout → CloudWatch Logs `/ol/<env>/app`. Metric: ALB/ECS/RDS có sẵn trong CloudWatch. Trace: OpenTelemetry SDK (`--import @ol/node-kit/otel-register`) → ADOT collector sidecar → X-Ray.
- **Thay thế bằng gì?** Datadog/New Relic/Grafana Cloud; Prometheus + Loki + Tempo tự vận hành.
- **Lợi thế khi chọn?** Không thêm nhà cung cấp, không vận hành cụm quan sát; OpenTelemetry là chuẩn mở → đổi backend chỉ đổi cấu hình collector.
- **Không dùng thì sao?** Sự cố được phát hiện qua khách hàng gọi điện.

#### SLI / SLO / error budget / burn rate
- **Nghĩa là gì?** SLI là chỉ số đo được (tỉ lệ request thành công); SLO là mục tiêu (99,5%/30 ngày); error budget là phần được phép lỗi (0,5%); burn rate là tốc độ tiêu ngân sách đó (14,4× = hết trong ~2 ngày).
- **Dùng thế nào?** `monitoring.tf`: hai composite alarm — *fast burn* (lỗi > 7,2% trong cả 1 giờ và 5 phút) và *slow burn* (> 3% trong cả 6 giờ và 30 phút).
- **Thay thế bằng gì?** Cảnh báo ngưỡng tĩnh "5xx > 10 trong 5 phút".
- **Lợi thế khi chọn?** Ít báo động giả (cửa sổ dài xác nhận, cửa sổ ngắn giúp tắt nhanh khi hết lỗi); mức nghiêm trọng gắn với ảnh hưởng thật.
- **Không dùng thì sao?** Hoặc bị cảnh báo liên tục và bắt đầu bỏ qua, hoặc bỏ lỡ lỗi kéo dài ở mức thấp.

#### Tắt êm (graceful shutdown) và health check
- **Nghĩa là gì?** `/health/live` = tiến trình còn sống; `/health/ready` = sẵn sàng nhận traffic (DB kết nối được). Khi nhận SIGTERM: báo not-ready, ngừng nhận kết nối mới, chờ request đang xử lý, đóng DB, thoát.
- **Dùng thế nào?** `startServer()` trong node-kit (thoát cưỡng bức sau 25 s < `stopTimeout` 30 s của ECS); ALB dùng `/health/ready`.
- **Thay thế bằng gì?** Để tiến trình bị kill.
- **Lợi thế khi chọn?** Mỗi lần deploy/scale-in không cắt ngang request.
- **Không dùng thì sao?** Mỗi lần triển khai sinh một loạt lỗi 502.

## 9.2 Log

Mỗi dòng log là JSON, có sẵn `requestId` và `principal` (nhờ `AsyncLocalStorage`), cùng `trace_id` khi OpenTelemetry bật. Header `X-Request-Id` được BFF tạo/chuyển tiếp và trả về cho trình duyệt → người dùng báo lỗi kèm mã này.

Truy vấn mẫu (CloudWatch → Logs Insights → log group `/ol/prod/app`):

```sql
-- 1. Lỗi 5xx gần nhất, kèm request id
fields @timestamp, @logStream, requestId, principal, method, route, status
| filter msg = "http_request" and status >= 500
| sort @timestamp desc
| limit 50
```

```sql
-- 2. Theo dấu một request qua mọi service
fields @timestamp, @logStream, level, msg, durationMs
| filter requestId = "REPLACE-REQUEST-ID"
| sort @timestamp asc
```

```sql
-- 3. p95 thời gian xử lý theo route trong 1 giờ
filter msg = "http_request"
| stats pct(durationMs, 95) as p95, count(*) as n by method, route
| sort p95 desc
```

```sql
-- 4. Từ chối phân quyền nhiều bất thường (dò quét/lỗi cấu hình quyền)
filter msg = "http_request" and status = 403
| stats count(*) as n by principal, route
| sort n desc
| limit 20
```

```sql
-- 5. IAM authorize không phản hồi (fail closed)
filter msg like /authorize/ and level >= 50
| stats count(*) by bin(5m)
```

> Access log của node-kit có dạng `{"msg":"http_request","method","route","status","durationMs","requestId","principal"}` (route là mẫu, ví dụ `/v1/tenants/:tenantId`). Lỗi chi tiết nằm ở dòng log riêng của `errorHandler` cùng `requestId`. `level >= 50` là `error` theo thang số của pino. Nếu truy vấn trả rỗng, mở một dòng log thật và chỉnh tên trường cho khớp.

Local: Grafana → Explore → Loki, lọc `{service_name="iam-service"}`.

## 9.3 Metric, dashboard, cảnh báo

Dashboard `ol-<env>` (CloudWatch → Dashboards): request & 5xx, độ trễ p50/p95/p99 từ ALB, CPU từng service, CPU/kết nối RDS.

| Alarm | Điều kiện | Ý nghĩa | Hành động (runbook Bước 10) |
|---|---|---|---|
| `ol-<env>-slo-fast-burn` | Tỉ lệ 5xx > 7,2% trong 1 h **và** 5 phút | Sự cố đang diễn ra | RB-01 |
| `ol-<env>-slo-slow-burn` | > 3% trong 6 h **và** 30 phút | Lỗi âm ỉ | RB-01 (mức thấp hơn) |
| `ol-<env>-latency-p95` | p95 > 300 ms trong 15 phút | Chậm so với NFR | RB-02 |
| `ol-<env>-unhealthy-<tg>` | Có target không khỏe | Task lỗi/không sẵn sàng | RB-03 |
| `ol-<env>-rds-cpu/storage/memory` | CPU > 80%, dung lượng trống < 2 GB, RAM trống < 128 MB | DB sắp quá tải | RB-04 |
| AWS Budgets | Chi phí dự báo > ngân sách | Chi phí | RB-06 |

Cảnh báo gửi qua SNS → email (`alarm_email`). Kênh chat (Slack…) thêm sau bằng AWS Chatbot hoặc webhook.

Kiểm thử đường cảnh báo (bạn chạy, sau khi đã **Confirm subscription**):

```bash
aws cloudwatch set-alarm-state --alarm-name ol-dev-latency-p95 --state-value ALARM --state-reason "Thử đường cảnh báo"
```

Kết quả đúng: email trong vài phút; alarm tự về `OK` ở chu kỳ đánh giá kế tiếp.

## 9.4 Trace

- Local: Grafana → Explore → Tempo. Mở một request bất kỳ từ UI → thấy span `bff → warehouse-service → iam-service (authorize) → postgres`.
- AWS: X-Ray → Traces (ADOT sidecar với cấu hình mặc định `ecs-default-config.yaml`). Bật/tắt bằng biến `adot_enabled` của module `platform` (áp cho iam-service, warehouse-service, bff).

> **[CHƯA XÁC MINH]** Image ADOT đang để tag `latest` (`modules/ecs-service/main.tf`, biến `adot_image`). Thay bằng tag phiên bản cụ thể trước khi lên prod. Cấu hình mặc định của ADOT cho ECS có thể khác giữa các phiên bản — kiểm tra trace xuất hiện trong X-Ray ở dev trước.

## 9.5 SLO ban đầu

| SLI | Cách đo | SLO (30 ngày) |
|---|---|---|
| Khả dụng | 1 − (ELB 5xx + Target 5xx) / RequestCount tại ALB | 99,5% |
| Độ trễ đọc | p95 `TargetResponseTime` | < 300 ms |
| Độ trễ ghi | p95 route ghi (Logs Insights #3) | < 800 ms |
| Đăng nhập | Smoke + E2E sau deploy | Đạt 100% lần deploy |

99,5% ≈ 3 giờ 36 phút lỗi/tháng — phù hợp một đội nhỏ, prod một NAT, không trực 24/7. Tăng SLO chỉ khi đã có trực ca và kiến trúc đa AZ hoàn toàn.

## 9.6 Cơ chế chịu lỗi đã có

| Cơ chế | Giá trị | Ở đâu |
|---|---|---|
| Timeout gọi IAM authorize | 300 ms, thử lại 1 lần có jitter | `HttpAuthorizer` |
| Cache quyết định | allow 30 s, deny 5 s, tối đa 10.000 mục | `CachingAuthorizer` |
| Fail closed | 503 + `Retry-After` | node-kit |
| Timeout lấy kết nối DB / câu lệnh | 3 s / 10 s | `database.ts` |
| Pool DB | `max` theo cấu hình; tổng = max × số task < `max_connections` RDS | `database.ts` |
| Timeout HTTP server | keep-alive 65 s (> idle 60 s của ALB), headers 66 s, request 70 s | `server.ts` |
| Token client credentials | Cache tới gần hết hạn, gộp yêu cầu đồng thời | `ClientCredentialsTokenProvider` |
| JWKS | Cache khóa; IdP tạm lỗi vẫn xác minh được token | `jose` |
| Idempotency | Header `Idempotency-Key` bắt buộc khi điều chỉnh tồn; trùng khóa → trả kết quả cũ | warehouse |
| Rate limit | BFF theo phiên/phút; WAF 2.000 request/5 phút/IP; Keycloak brute-force | BFF, WAF, realm |
| Autoscaling | CPU 60%, min/max trong `deploy/<env>/*.yaml` | ECS |
| Circuit breaker triển khai | Tự rollback | ECS |
| Multi-AZ | RDS prod; task trải 2 AZ | Terraform |

Chưa có (thêm khi cần): circuit breaker phía client cho gọi giữa service (hiện chỉ có 1 phụ thuộc đồng bộ là IAM, đã có cache + timeout), hàng đợi bất đồng bộ (thêm khi có luồng IoT/webhook — Bước 10 mục mở rộng).

## 9.7 Load test

**Nơi chạy:** dev hoặc staging (không chạy vào prod). Dev không có WAF; staging có WAF 2.000 request/5 phút/IP — tăng tạm `waf_rate_limit` trong `envs/staging/terraform.tfvars` qua PR, trả lại sau khi xong.

Chuẩn bị: 3–5 tài khoản kiểm thử (rate limit BFF tính theo phiên), một kho và một mặt hàng; lấy cookie `__Host-ol_session` của từng tài khoản trong DevTools.

```powershell
Set-Location D:\Coding\DevOps\ol-platform\ol-infra
$env:BASE_URL = 'https://app.dev.<domain>'
$env:SESSIONS = Read-Host 'Dán các cookie, phân tách bằng dấu phẩy' -MaskInput   # Không lưu vào file/lịch sử
$env:TENANT_ID = '<uuid>'; $env:WAREHOUSE_ID = '<uuid>'; $env:ITEM_ID = '<uuid>'
$env:WSLENV = 'BASE_URL/u:SESSIONS/u:TENANT_ID/u:WAREHOUSE_ID/u:ITEM_ID/u'
Get-Content loadtest/warehouse.js -Raw | wsl -e docker run --rm -i -e BASE_URL -e SESSIONS -e TENANT_ID -e WAREHOUSE_ID -e ITEM_ID grafana/k6 run -
```

Kết quả đúng: k6 thoát mã 0 (lỗi < 1%, p95 đọc < 300 ms, p95 ghi < 800 ms) qua 10 phút 50 req/s + đột biến 200 req/s. Đồng thời quan sát dashboard: autoscaling thêm task, CPU RDS < 80%. Ghi kết quả vào `ol-handbook/docs/reports/` (tạo mới) kèm commit của từng service.

> Dev dùng Fargate Spot và RDS `db.t4g.micro` — kết quả ở dev chỉ là cận dưới. Nghiệm thu hiệu năng chính thức chạy ở staging với cấu hình gần prod (tạm nâng `rds_instance_class`).

## 9.8 Diễn tập lỗi (chạy ở dev/staging)

| # | Gây lỗi | Lệnh | Kết quả đúng |
|---|---|---|---|
| 1 | IAM ngừng | `aws ecs update-service --cluster ol-dev --service iam-service --desired-count 0` | Quyền đã cache: vẫn phục vụ ≤ 30 s; sau đó API kho trả `503` (không phải 200); alarm unhealthy; bật lại → tự hồi phục |
| 2 | Kill một task warehouse | `aws ecs stop-task --cluster ol-dev --task <arn>` | ECS tạo task mới; nếu ≥ 2 task: không có lỗi phía người dùng |
| 3 | DB khởi động lại | `aws rds reboot-db-instance --db-instance-identifier ol-dev` | `/health/ready` đỏ trong lúc reboot, request lỗi 503 ngắn; tự hồi phục không cần khởi động lại service |
| 4 | Keycloak ngừng | `desired-count 0` cho keycloak | Đăng nhập mới lỗi; người đã đăng nhập dùng tiếp tới khi cần refresh; API máy (token còn hạn) vẫn chạy |
| 5 | Triển khai image hỏng | Kịch bản 7.7 #6 | Circuit breaker rollback |

Sau mỗi bài: bật lại (`desired-count` về giá trị trong `deploy/<env>/*.yaml` hoặc chạy lại `deploy.yml`), ghi nhận thời gian phát hiện/hồi phục.

## 9.9 Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Xử lý |
|---|---|---|
| Không có trace trong X-Ray | Thiếu quyền X-Ray ở task role, hoặc ADOT image/config không như mong đợi | Log stream `<service>-otel`; kiểm `OTEL_EXPORTER_OTLP_ENDPOINT` |
| Alarm `INSUFFICIENT_DATA` ngoài giờ | Dev/staging tắt ngoài giờ | Đã đặt `treat_missing_data = notBreaching` cho môi trường tắt ngoài giờ |
| Load test toàn `403` | WAF chặn theo IP hoặc thiếu header CSRF | Tăng `waf_rate_limit` tạm thời; kiểm script gửi `X-OL-CSRF` |
| Load test toàn `429` | Rate limit BFF theo phiên | Thêm tài khoản/phiên vào `SESSIONS` |

## 9.10 Hoàn tác

Mọi thay đổi ngưỡng/alarm/WAF đi qua PR `ol-infra` → revert được. Diễn tập: đưa `desired-count` về giá trị Git bằng cách chạy lại `deploy.yml` cho môi trường đó.
