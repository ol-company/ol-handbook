## Thay đổi gì và vì sao

<!-- Tiêu đề PR phải theo Conventional Commits, ví dụ: feat(iam): thêm API mời người dùng.
     PR được squash-merge nên tiêu đề PR trở thành commit message trên main. -->

## Liên kết

- Issue/ADR liên quan: #

## Loại thay đổi

- [ ] Tính năng mới
- [ ] Sửa lỗi
- [ ] Thay đổi phá vỡ tương thích (breaking change) — đã ghi `!` trong tiêu đề
- [ ] Hạ tầng / cấu hình / pipeline
- [ ] Tài liệu

## Kiểm tra

- [ ] Đã chạy test liên quan ở local (ghi lệnh và kết quả bên dưới)
- [ ] Đã thêm/cập nhật test cho hành vi mới
- [ ] Với thay đổi phân quyền: có test cho truy cập hợp lệ, thiếu quyền và chéo tenant
- [ ] Với migration DB: tương thích ngược (expand/contract), đã thử rollback
- [ ] Không có secret, token, mật khẩu trong diff

```text
<dán output test ở đây>
```

## Rủi ro và cách hoàn tác

<!-- Điều gì có thể hỏng sau khi merge/deploy? Hoàn tác bằng cách nào? -->
