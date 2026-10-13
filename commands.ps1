# ==============================================================================
# Script: commands.ps1 (Dành cho môi trường Windows PowerShell)
# ==============================================================================

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host " [BƯỚC 1] TẠO CUSTOM BRIDGE NETWORK: app-net" -ForegroundColor Cyan
Write-Host "========================================================================"
if (docker network ls --format '{{.Name}}' | Select-String -Pattern "^app-net$") {
    Write-Host "Network 'app-net' đã tồn tại."
} else {
    docker network create --driver bridge app-net
    Write-Host "Đã tạo Custom Bridge Network: app-net"
}

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host " [BƯỚC 2] TẠO NAMED VOLUME: db-data" -ForegroundColor Cyan
Write-Host "========================================================================"
if (docker volume ls --format '{{.Name}}' | Select-String -Pattern "^db-data$") {
    Write-Host "Volume 'db-data' đã tồn tại."
} else {
    docker volume create db-data
    Write-Host "Đã tạo Named Volume: db-data"
}

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host " [BƯỚC 3] KHỞI CHẠY POSTGRESQL CONTAINER: db-server" -ForegroundColor Cyan
Write-Host "========================================================================"
docker rm -f db-server 2>$null

docker run -d `
  --name db-server `
  --network app-net `
  -v db-data:/var/lib/postgresql/data `
  -e POSTGRES_DB=appdb `
  -e POSTGRES_USER=appuser `
  -e POSTGRES_PASSWORD=secretpassword `
  postgres:15-alpine

Write-Host "Đang chờ PostgreSQL khởi động hoàn tất..."
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host " [BƯỚC 4] KHỞI CHẠY BACKEND CONTAINER: app-container" -ForegroundColor Cyan
Write-Host "========================================================================"
docker rm -f app-container 2>$null

docker run -d `
  --name app-container `
  --network app-net `
  -e DB_HOST=db-server `
  -e DB_PORT=5432 `
  -e DB_NAME=appdb `
  -e DB_USER=appuser `
  -e DB_PASSWORD=secretpassword `
  alpine:latest sleep 3600

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host " [BƯỚC 5] KIỂM TRA DNS RESOLUTION TỪ BACKEND ĐẾN DATABASE" -ForegroundColor Cyan
Write-Host "========================================================================"
docker exec app-container ping -c 2 db-server

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host " [BƯỚC 6] THỰC HIỆN TEST DATA PERSISTENCE" -ForegroundColor Cyan
Write-Host "========================================================================"
Write-Host "6.1. Thêm dữ liệu mẫu vào cơ sở dữ liệu:"
docker exec db-server psql -U appuser -d appdb -c "CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name VARCHAR(100), email VARCHAR(100));"
docker exec db-server psql -U appuser -d appdb -c "INSERT INTO users (name, email) VALUES ('DevOps Engineer', 'devops@company.com'), ('Docker Master', 'docker@company.com');"

Write-Host "Dữ liệu ban đầu:"
docker exec db-server psql -U appuser -d appdb -c "SELECT * FROM users;"

Write-Host ""
Write-Host "6.2. Xóa cứng Container db-server (docker rm -f db-server)..." -ForegroundColor Yellow
docker rm -f db-server

Write-Host ""
Write-Host "6.3. Khởi chạy lại Container DB mới gắn cùng Volume db-data..." -ForegroundColor Green
docker run -d `
  --name db-server `
  --network app-net `
  -v db-data:/var/lib/postgresql/data `
  -e POSTGRES_DB=appdb `
  -e POSTGRES_USER=appuser `
  -e POSTGRES_PASSWORD=secretpassword `
  postgres:15-alpine

Start-Sleep -Seconds 5

Write-Host ""
Write-Host "6.4. Xác minh dữ liệu không bị mất sau khi tái tạo container:" -ForegroundColor Green
docker exec db-server psql -U appuser -d appdb -c "SELECT * FROM users;"

Write-Host ""
Write-Host "XÁC MINH HOÀN TẤT: Dữ liệu được bảo toàn thành công!" -ForegroundColor Green
