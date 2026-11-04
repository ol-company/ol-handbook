# OL-Platform Handbook

Sổ tay xây dựng và vận hành **OL-Platform** — nền tảng logistics/supply-chain (kho, đơn hàng, giao vận, Camera AI, robot, IoT, tích hợp đối tác) — từ số 0 tới production.

Repo này là **docs-as-code**: mọi quyết định kiến trúc, hướng dẫn từng bước, runbook và script khởi tạo đều nằm trong Git, được review qua Pull Request như code.

## Lộ trình

"Đã viết" = tài liệu + code/cấu hình đầy đủ, **chưa** được chạy trên môi trường thật. Chỉ đổi sang "Đã nghiệm thu" khi có bằng chứng (link CI run, output lệnh, ảnh dashboard).

| Bước | Nội dung | Tài liệu | Trạng thái |
|---|---|---|---|
| 0 | Kiến trúc, stack, mục tiêu phi chức năng | [docs/00-kien-truc-va-quyet-dinh.md](docs/00-kien-truc-va-quyet-dinh.md) | Đã chốt (v0.2) |
| 1 | Công cụ và GitHub Organization | [docs/01-cong-cu-va-github.md](docs/01-cong-cu-va-github.md) | Đã viết |
| 2 | Source code và môi trường local | [docs/02-source-code-va-local.md](docs/02-source-code-va-local.md) | Đã viết |
| 3 | IAM và tích hợp | [docs/03-iam-va-tich-hop.md](docs/03-iam-va-tich-hop.md) | Đã viết |
| 4 | Docker và build config | [docs/04-docker-va-build-config.md](docs/04-docker-va-build-config.md) | Đã viết |
| 5 | CI và kiểm thử | [docs/05-ci-va-kiem-thu.md](docs/05-ci-va-kiem-thu.md) | Đã viết |
| 6 | Hạ tầng AWS bằng Terraform | [docs/06-ha-tang-aws-terraform.md](docs/06-ha-tang-aws-terraform.md) | Đã viết |
| 7 | CD và phát hành | [docs/07-cd-va-phat-hanh.md](docs/07-cd-va-phat-hanh.md) | Đã viết |
| 8 | Dữ liệu và bảo mật | [docs/08-du-lieu-va-bao-mat.md](docs/08-du-lieu-va-bao-mat.md) | Đã viết |
| 9 | Quan sát và độ tin cậy | [docs/09-quan-sat-va-do-tin-cay.md](docs/09-quan-sat-va-do-tin-cay.md) | Đã viết |
| 10 | Nghiệm thu, vận hành, bảo trì | [docs/10-nghiem-thu-van-hanh.md](docs/10-nghiem-thu-van-hanh.md) | Đã viết |

## Các repo

| Repo | Vai trò |
|---|---|
| `ol-handbook` | Tài liệu, script khởi tạo GitHub, template |
| `ol-node-kit` | Thư viện dùng chung: lỗi, logger, xác minh JWT, authorizer, `SecureRouter`, health, shutdown, `withTenant` |
| `ol-iam-service` | Tenant/user/group/role/binding, API quản trị, API `authorize`, audit |
| `ol-warehouse-service` | Service nghiệp vụ đầu tiên: kho, mặt hàng, nhập/xuất (RLS) |
| `ol-bff` | OIDC client, session phía server, proxy `/api/*` |
| `ol-web-admin` | Frontend quản trị (React + Vite) |
| `ol-build-tooling` | Dockerfile tập trung, reusable workflow (CI, quét bảo mật, build image, release) |
| `ol-infra` | Terraform, build config, deploy YAML theo môi trường, realm Keycloak, stack local, workflow deploy |

## Cấu trúc repo này

```text
ol-handbook/
├── README.md
├── docs/                              # 00–10: hướng dẫn từng bước
├── bootstrap/
│   ├── replace-placeholders.ps1       # Điền __ORG__, __DOMAIN__, account ID... vào mọi repo
│   └── github/
│       ├── check-tools.ps1            # Kiểm tra công cụ trên máy
│       ├── bootstrap-github.ps1       # Khởi tạo org, team, repo, ruleset, environment
│       ├── set-required-checks.ps1    # Bật check bắt buộc (Bước 5)
│       └── config/                    # teams, repos, rulesets, environments, required-checks
└── templates/
    ├── org-dot-github/                # Seed cho repo .github
    └── repo-template/                 # Seed cho ol-repo-template
```

## Nội dung chưa xác minh

Các mục sau lấy theo hiểu biết tại thời điểm viết, cần bạn kiểm tra trước khi dùng (tìm `[CHƯA XÁC MINH]` trong các repo):

- Tag image: `quay.io/keycloak/keycloak:26.8.1`, `adorsys/keycloak-config-cli:6.4.0-26.1.0`, Mailpit, `grafana/otel-lgtm`, ADOT collector (`latest` — cần pin), Trivy/gitleaks/hadolint/actionlint trong `ol-build-tooling/tool-versions.env`.
- ID winget: lefthook, gitleaks, mkcert, Terraform, AWS CLI.
- Trường API GitHub: `sha_pinning_required`, `allowed_merge_methods` (script có đường lui), ID app GitHub Actions `15368` cho check bắt buộc.
- Dependabot: khả năng đọc `vars` và hỗ trợ token GitHub App cho registry riêng.
- Selector form đăng nhập Keycloak trong E2E.
- Quy trình hoán đổi instance RDS sau khôi phục + `terraform import`.
- Mọi con số chi phí.

## Quy ước của sổ tay

- Mỗi bước có đủ: **Mục tiêu → Đầu vào → Nơi thao tác → File tạo/sửa → Lệnh/code → Kết quả mong đợi → Cách kiểm tra → Lỗi thường gặp → Hoàn tác**.
- Mỗi công nghệ/thư viện được trả lời 5 câu tách riêng: *Nghĩa là gì? Dùng thế nào? Thay thế bằng gì? Lợi thế khi chọn? Không dùng thì sao?*
- Mỗi dòng code/lệnh quan trọng đều có chú thích ngay cạnh.
- Nội dung chưa được kiểm chứng trên môi trường thật được đánh dấu **[CHƯA XÁC MINH]**.
- Không bao giờ dán mật khẩu, token, private key vào tài liệu, issue hay hội thoại.
