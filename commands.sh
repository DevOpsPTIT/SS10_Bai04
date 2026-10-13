#!/bin/bash
# ==============================================================================
# Script: commands.sh
# Mục tiêu: Thiết lập Custom Network, Named Volume và kiểm thử Data Persistence
# ==============================================================================

set -e

echo "========================================================================"
echo " [BƯỚC 1] TẠO CUSTOM BRIDGE NETWORK: app-net"
echo "========================================================================"
if docker network inspect app-net >/dev/null 2>&1; then
    echo "Network 'app-net' đã tồn tại. Bỏ qua tạo mới."
else
    docker network create --driver bridge app-net
    echo "Đã tạo Custom Bridge Network: app-net thành công."
fi

echo ""
echo "========================================================================"
echo " [BƯỚC 2] TẠO NAMED VOLUME: db-data"
echo "========================================================================"
if docker volume inspect db-data >/dev/null 2>&1; then
    echo "Volume 'db-data' đã tồn tại. Bỏ qua tạo mới."
else
    docker volume create db-data
    echo "Đã tạo Named Volume: db-data thành công."
fi

echo ""
echo "========================================================================"
echo " [BƯỚC 3] KHỞI CHẠY POSTGRESQL CONTAINER: db-server"
echo "========================================================================"
# Dọn dẹp container cũ nếu đang chạy
docker rm -f db-server >/dev/null 2>&1 || true

docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_DB=appdb \
  -e POSTGRES_USER=appuser \
  -e POSTGRES_PASSWORD=secretpassword \
  postgres:15-alpine

echo "Đang chờ PostgreSQL sẵn sàng nhận kết nối..."
until docker exec db-server pg_isready -U appuser -d appdb >/dev/null 2>&1; do
  echo "Chờ PostgreSQL khởi động..."
  sleep 2
done
echo "PostgreSQL đã sẵn sàng hoạt động!"

echo ""
echo "========================================================================"
echo " [BƯỚC 4] KHỞI CHẠY BACKEND CONTAINER: app-container"
echo "========================================================================"
docker rm -f app-container >/dev/null 2>&1 || true

# Sử dụng container chạy Alpine có sẵn ping, curl và psql-client để kiểm thử kết nối
docker run -d \
  --name app-container \
  --network app-net \
  -e DB_HOST=db-server \
  -e DB_PORT=5432 \
  -e DB_NAME=appdb \
  -e DB_USER=appuser \
  -e DB_PASSWORD=secretpassword \
  alpine:latest sleep 3600

echo "Đã khởi chạy Backend container 'app-container' kết nối vào 'app-net'."

echo ""
echo "========================================================================"
echo " [BƯỚC 5] KIỂM TRA DNS RESOLUTION TỪ BACKEND ĐẾN DATABASE"
echo "========================================================================"
echo "Thực hiện lệnh: docker exec app-container ping -c 2 db-server"
docker exec app-container ping -c 2 db-server
echo "-> DNS resolution thành công! app-container đã phân giải được IP của db-server."

echo ""
echo "========================================================================"
echo " [BƯỚC 6] THỰC HIỆN TEST DATA PERSISTENCE"
echo "========================================================================"
echo "--- 6.1. Thêm dữ liệu mẫu vào cơ sở dữ liệu ---"
docker exec -i db-server psql -U appuser -d appdb << 'EOF'
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (name, email) VALUES 
('DevOps Engineer', 'devops@company.com'),
('Docker Master', 'docker@company.com');
EOF

echo "Dữ liệu ban đầu trong bảng users:"
docker exec db-server psql -U appuser -d appdb -c "SELECT * FROM users;"

echo ""
echo "--- 6.2. Xóa cứng Container db-server (docker rm -f) ---"
docker rm -f db-server
echo "Container db-server đã bị xóa hoàn toàn khỏi hệ thống!"

echo ""
echo "--- 6.3. Khởi chạy lại Container DB mới gắn cùng Volume db-data ---"
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_DB=appdb \
  -e POSTGRES_USER=appuser \
  -e POSTGRES_PASSWORD=secretpassword \
  postgres:15-alpine

echo "Đang chờ PostgreSQL mới phục hồi và sẵn sàng..."
until docker exec db-server pg_isready -U appuser -d appdb >/dev/null 2>&1; do
  sleep 2
done

echo ""
echo "--- 6.4. Xác minh dữ liệu không bị mất sau khi tái tạo container ---"
docker exec db-server psql -U appuser -d appdb -c "SELECT * FROM users;"

echo ""
echo "========================================================================"
echo " XÁC MINH HOÀN TẤT: Dữ liệu được bảo toàn 100% nhờ Named Volume db-data!"
echo "========================================================================"
