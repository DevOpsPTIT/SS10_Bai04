# BÀI 4: THIẾT LẬP CUSTOM NETWORK & NAMED VOLUME BẰNG DOCKER CLI

## 1. Mục tiêu & Bối cảnh kỹ thuật
- **Bối cảnh:** Triển khai thủ công một cụm dịch vụ gồm 2 Container: **Backend Web Service (`app-container`)** và **PostgreSQL Database (`db-server`)** bằng Docker CLI.
- **Mục tiêu kỹ thuật:**
  1. Tạo **Custom Bridge Network** (`app-net`) để kích hoạt cơ chế tự động phân giải tên miền nội bộ (**Embedded DNS Resolution**), cho phép các container giao tiếp với nhau bằng chính container name thay vì IP tĩnh.
  2. Tạo **Named Volume** (`db-data`) để lưu trữ dữ liệu cơ sở dữ liệu bền vững (**Data Persistence**), đảm bảo dữ liệu không bị xóa khi container bị xóa bỏ hoặc gặp sự cố.
  3. Kiểm chứng quá trình phục hồi dữ liệu sau khi xóa cứng container (`docker rm -f`).

---

## 2. Cấu trúc thư mục

```text
Bai04/
├── commands.sh         # Script tự động hóa toàn bộ quy trình (Bash shell)
├── commands.ps1        # Script hỗ trợ môi trường Windows PowerShell
└── README.md           # Tài liệu hướng dẫn phân tích kiến trúc và kiểm thử
```

---

## 3. Phân tích chuyên sâu kiến trúc Network & Volume

### 3.1. Custom Bridge Network vs Default Bridge Network

```
+---------------------------------------------------------------------------------+
|                         Docker Host (Physical / VM)                             |
|                                                                                 |
|   +-------------------------------------------------------------------------+   |
|   |                   Custom Bridge Network: app-net                        |   |
|   |                   (Embedded DNS Server: 127.0.0.11)                     |   |
|   |                                                                         |   |
|   |   +---------------------+   DNS: "db-server"    +-------------------+   |   |
|   |   |    app-container    | --------------------> |     db-server     |   |   |
|   |   |  (Backend Service)  |    (Port 5432 TCP)    |   (PostgreSQL)    |   |   |
|   |   +---------------------+                       +-------------------+   |   |
|   +-----------------------------------------------------------|-------------+   |
|                                                               |                 |
|                                                    Mount: -v db-data:...        |
|                                                               v                 |
|                                                     +-------------------+       |
|                                                     |   Named Volume:   |       |
|                                                     |      db-data      |       |
|                                                     | (/var/lib/docker) |       |
|                                                     +-------------------+       |
+---------------------------------------------------------------------------------+
```

- **Mạng mặc định (`bridge`):** Mặc định khi chạy `docker run`, container được gắn vào mạng bridge mặc định. Tuy nhiên, mạng này **KHÔNG** hỗ trợ phân giải tên miền (Service Discovery by Name) trừ khi dùng cờ cũ `--link` (đã bị deprecated). Muốn giao tiếp bắt buộc phải biết IP nội bộ của container khác (vốn thay đổi sau mỗi lần khởi động lại).
- **Custom Bridge Network (`app-net`):** Khi tạo một mạng custom bằng `docker network create`, Docker tự động tích hợp một **Embedded DNS Server** tại địa chỉ `127.0.0.11`. Khi `app-container` gọi hostname `db-server`, daemon DNS sẽ tự động phân giải thành địa chỉ IP nội bộ tương ứng trong subnet.

### 3.2. Named Volume & Cơ chế Data Persistence
- Mặc định, mọi dữ liệu ghi bên trong container được lưu trên tầng ghi chép tạm thời (**Writable Container Layer**). Khi container bị xóa (`docker rm`), tầng này bị hủy bỏ hoàn toàn.
- **Named Volume (`db-data`):** Được Docker quản lý tập trung trên Host (thông thường tại `/var/lib/docker/volumes/db-data/_data`).
- Vòng đời của Named Volume hoàn toàn **độc lập** với vòng đời của Container. Khi container DB bị xóa cứng (`docker rm -f`), thư mục dữ liệu PostgreSQL trên ổ cứng vẫn giữ nguyên vẹn. Khi một container mới được mount vào cùng Volume, nó sẽ lập tức đọc lại toàn bộ database sẵn có mà không cần tạo lại từ đầu.

---

## 4. Hướng dẫn thực thi & Kiểm tra từng bước

### Cách 1: Chạy tự động toàn bộ bằng Script
Nếu sử dụng môi trường Linux / macOS / Git Bash / WSL:
```bash
chmod +x commands.sh
./commands.sh
```

Nếu sử dụng PowerShell trên Windows:
```powershell
.\commands.ps1
```

---

### Cách 2: Thực thi thủ công từng lệnh Docker CLI

#### Bước 1: Tạo Custom Bridge Network
```bash
docker network create --driver bridge app-net
```
*Kiểm tra danh sách mạng:*
```bash
docker network ls | grep app-net
```

#### Bước 2: Tạo Named Volume
```bash
docker volume create db-data
```
*Kiểm tra danh sách volume:*
```bash
docker volume ls | grep db-data
```

#### Bước 3: Khởi chạy Database Container gắn Network và Volume
```bash
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_DB=appdb \
  -e POSTGRES_USER=appuser \
  -e POSTGRES_PASSWORD=secretpassword \
  postgres:15-alpine
```

#### Bước 4: Khởi chạy Backend Container tham gia cùng Network
```bash
docker run -d \
  --name app-container \
  --network app-net \
  -e DB_HOST=db-server \
  -e DB_PORT=5432 \
  -e DB_NAME=appdb \
  -e DB_USER=appuser \
  -e DB_PASSWORD=secretpassword \
  alpine:latest sleep 3600
```

#### Bước 5: Kiểm tra DNS Resolution qua ping
Kiểm tra khả năng phân giải hostname `db-server` từ bên trong `app-container`:
```bash
docker exec -it app-container ping -c 2 db-server
```
**Kết quả mong đợi:**
```text
PING db-server (172.18.0.2): 56 data bytes
64 bytes from 172.18.0.2: seq=0 ttl=64 time=0.082 ms
64 bytes from 172.18.0.2: seq=1 ttl=64 time=0.065 ms

--- db-server ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
```

#### Bước 6: Kiểm tra chi tiết cấu hình mạng bằng `network inspect`
```bash
docker network inspect app-net
```
Trong đầu ra JSON, kiểm tra mục `Containers`: cả `db-server` và `app-container` đều cùng thuộc dải mạng (Subnet), có IPv4 Address nội bộ riêng biệt.

---

## 5. Kịch bản kiểm thử Data Persistence (Bảo toàn dữ liệu)

### Bước 1: Thêm dữ liệu mẫu vào cơ sở dữ liệu
Thực thi lệnh SQL tạo bảng `users` và chèn 2 bản ghi:

```bash
docker exec -i db-server psql -U appuser -d appdb -c "
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100)
);
INSERT INTO users (name, email) VALUES 
('DevOps Engineer', 'devops@company.com'),
('Docker Master', 'docker@company.com');
"
```

Kiểm tra dữ liệu hiện có:
```bash
docker exec db-server psql -U appuser -d appdb -c "SELECT * FROM users;"
```

**Kết quả:**
```text
 id |      name       |        email        
----+-----------------+---------------------
  1 | DevOps Engineer | devops@company.com
  2 | Docker Master   | docker@company.com
(2 rows)
```

### Bước 2: Xóa cứng Container Database
Thực hiện xóa cưỡng bức container `db-server`:
```bash
docker rm -f db-server
```
Kiểm tra lại bằng `docker ps -a`: Container `db-server` đã biến mất hoàn toàn.

### Bước 3: Khởi chạy lại Container Database mới gắn cùng Volume `db-data`
```bash
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_DB=appdb \
  -e POSTGRES_USER=appuser \
  -e POSTGRES_PASSWORD=secretpassword \
  postgres:15-alpine
```

### Bước 4: Xác minh dữ liệu không bị mất
Chờ 3-5 giây cho PostgreSQL khởi động xong, sau đó truy vấn lại dữ liệu:

```bash
docker exec db-server psql -U appuser -d appdb -c "SELECT * FROM users;"
```

**Kết quả:**
```text
 id |      name       |        email        
----+-----------------+---------------------
  1 | DevOps Engineer | devops@company.com
  2 | Docker Master   | docker@company.com
(2 rows)
```
> **Kết luận:** Mặc dù container `db-server` cũ đã bị hủy diệt hoàn toàn, container mới khởi tạo vẫn truy xuất đầy đủ 100% dữ liệu nhờ **Named Volume `db-data`**.

---

## 6. Dọn dẹp tài nguyên sau bài thực hành

```bash
# Dừng và xóa các container
docker rm -f db-server app-container

# Xóa mạng custom
docker network rm app-net

# Xóa Named Volume (Cảnh báo: Dữ liệu DB sẽ bị xóa vĩnh viễn)
docker volume rm db-data
```
