# Quy trình đóng góp

## Nhánh và Pull Request

1. Không push trực tiếp lên `main` (ruleset sẽ chặn).
2. Tạo nhánh từ `main`: `feat/iam-invite-user`, `fix/bff-refresh-race`, `chore/bump-node-26`.
3. Mở Pull Request; **tiêu đề PR theo Conventional Commits** vì PR được squash-merge và tiêu đề trở thành commit trên `main`.
4. Mọi check bắt buộc phải xanh; mọi hội thoại review phải được resolve.
5. Sau khi merge, nhánh tự xóa.

## Conventional Commits

```text
<type>(<scope>)!: <mô tả ngắn, thể mệnh lệnh>
```

| type | Khi nào | Ảnh hưởng version (SemVer) |
|---|---|---|
| `feat` | Thêm tính năng | minor |
| `fix` | Sửa lỗi | patch |
| `perf` | Cải thiện hiệu năng | patch |
| `refactor` | Đổi cấu trúc, không đổi hành vi | không |
| `test` | Thêm/sửa test | không |
| `docs` | Tài liệu | không |
| `build` | Build system, Dockerfile, dependency | không |
| `ci` | Pipeline | không |
| `chore` | Việc lặt vặt khác | không |
| `revert` | Hoàn tác commit | tùy |

- `scope` là module: `iam`, `bff`, `warehouse`, `web`, `infra`, `build`...
- Dấu `!` hoặc footer `BREAKING CHANGE:` → tăng major.

## Ký commit

Commit cục bộ nên được ký bằng SSH key (hướng dẫn trong `ol-handbook/docs/01-cong-cu-va-github.md`). Commit trên `main` được GitHub ký khi squash-merge.

## Bí mật

Không bao giờ commit `.env`, private key, token. Hook `gitleaks` chặn ở máy bạn; secret scanning chặn ở GitHub. Nếu lỡ commit: **xem bí mật đó đã bị lộ** → thu hồi/xoay vòng ngay, sau đó mới dọn lịch sử.
