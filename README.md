# OneDrive to Google Drive Auto Sync

自動將 OneDrive 檔案同步到 Google Drive 的微服務，使用 Rclone 實現，可部署到 Zeabur 或任何支援 Docker 的平台。

## 功能特色

- 單向同步：OneDrive → Google Drive
- 可設定同步間隔（預設 30 分鐘）
- 支援指定資料夾同步
- Docker 容器化，易於部署
- 支援 Zeabur 一鍵部署

## 架構說明

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   OneDrive  │ ───► │   Rclone    │ ───► │Google Drive │
│  (來源)     │      │  (Zeabur)   │      │  (目標)     │
└─────────────┘      └─────────────┘      └─────────────┘
```

## 快速開始

### 步驟 1：設定 Rclone

在本機安裝 Rclone 並設定雲端硬碟授權：

```bash
# 安裝 Rclone (Windows)
winget install Rclone.Rclone

# 或使用 Chocolatey
choco install rclone

# macOS / Linux
curl https://rclone.org/install.sh | sudo bash
```

### 步驟 2：授權 OneDrive

```bash
rclone config

# 選擇 n (新建)
# 名稱輸入: onedrive
# 類型選擇: onedrive
# 依照提示完成 OAuth 授權
```

### 步驟 3：授權 Google Drive

```bash
rclone config

# 選擇 n (新建)
# 名稱輸入: gdrive
# 類型選擇: drive
# scope 選擇: drive (完整存取)
# 依照提示完成 OAuth 授權
```

### 步驟 4：匯出設定

```bash
# 顯示設定內容
rclone config show

# 將設定轉為 Base64（用於 Zeabur 環境變數）
rclone config show | base64
```

### 步驟 5：部署到 Zeabur

1. Fork 此專案到你的 GitHub
2. 在 [Zeabur](https://zeabur.com) 建立新專案
3. 選擇從 GitHub 部署
4. 設定環境變數（見下方說明）

## 環境變數

| 變數名稱 | 必填 | 說明 | 範例 |
|---------|------|------|------|
| `RCLONE_CONF_BASE64` | 是* | Rclone 設定檔（Base64 編碼） | `W29uZWRyaXZlXQ...` |
| `RCLONE_CONF_CONTENT` | 是* | Rclone 設定檔（純文字） | `[onedrive]...` |
| `RCLONE_SOURCE` | 否 | 來源路徑 | `onedrive:材料明細` |
| `RCLONE_DEST` | 否 | 目標路徑 | `gdrive:材料明細` |
| `SYNC_INTERVAL` | 否 | 同步間隔（秒） | `1800`（30分鐘） |
| `RCLONE_TRANSFERS` | 否 | 並行傳輸數 | `4` |
| `ALERT_EMAIL` | 否 | 警報通知信箱 | `your@email.com` |
| `SENDGRID_API_KEY` | 否 | SendGrid API Key | `SG.xxxxx` |

> *`RCLONE_CONF_BASE64` 或 `RCLONE_CONF_CONTENT` 擇一設定即可，建議使用 Base64 編碼避免特殊字元問題。

## 郵件警報設定（選用）

當 Token 過期或同步連續失敗時，服務會自動發送郵件通知。

### 步驟 1：註冊 SendGrid（免費）

1. 前往 [SendGrid](https://sendgrid.com) 註冊帳號
2. 免費方案每天可發送 100 封郵件

### 步驟 2：建立 API Key

1. 登入 SendGrid Dashboard
2. 前往 Settings → API Keys
3. 點擊 "Create API Key"
4. 選擇 "Restricted Access"，僅啟用 "Mail Send"
5. 複製產生的 API Key（只會顯示一次）

### 步驟 3：設定環境變數

在 Zeabur 設定以下環境變數：

```bash
ALERT_EMAIL=ipod0224@gmail.com
SENDGRID_API_KEY=SG.xxxxxxxxxxxxxxxxxxxxxxxx
```

### 警報觸發條件

| 事件 | 說明 |
|------|------|
| Token 過期 | OneDrive 或 Google Drive 授權失效 |
| 連續失敗 3 次 | 同步連續失敗 3 次以上 |

## 設定範例

### 同步特定資料夾

```bash
# 同步 OneDrive 的「材料明細」到 Google Drive 的「材料明細」
RCLONE_SOURCE=onedrive:材料明細
RCLONE_DEST=gdrive:材料明細
```

### 同步整個 OneDrive

```bash
# 同步整個 OneDrive 到 Google Drive 的「OneDrive-Backup」資料夾
RCLONE_SOURCE=onedrive:
RCLONE_DEST=gdrive:OneDrive-Backup
```

### 調整同步頻率

```bash
# 每 5 分鐘同步一次
SYNC_INTERVAL=300

# 每 30 分鐘同步一次
SYNC_INTERVAL=1800

# 每小時同步一次
SYNC_INTERVAL=3600
```

## 本機測試

```bash
# 建立 Docker 映像
docker build -t onedrive-gdrive-sync .

# 執行容器
docker run -d \
  -e RCLONE_CONF_BASE64="你的Base64設定" \
  -e RCLONE_SOURCE="onedrive:材料明細" \
  -e RCLONE_DEST="gdrive:材料明細" \
  -e SYNC_INTERVAL=1800 \
  onedrive-gdrive-sync
```

## 檔案結構

```
onedrive-gdrive-sync/
├── Dockerfile          # Docker 映像定義
├── entrypoint.sh       # 啟動腳本（同步邏輯）
├── zeabur.json         # Zeabur 部署設定
├── .gitignore          # Git 忽略檔案
├── .env.example        # 環境變數範例
└── README.md           # 說明文件
```

## 注意事項

### 同步方向

此服務是**單向同步**，只會將 OneDrive 的變更同步到 Google Drive：
- OneDrive 新增檔案 → Google Drive 新增
- OneDrive 修改檔案 → Google Drive 更新
- OneDrive 刪除檔案 → Google Drive 刪除

⚠️ **在 Google Drive 上的修改會在下次同步時被覆蓋**

### Token 過期

OAuth Token 會自動更新，但如果長時間未使用可能會過期。若遇到授權問題，請重新執行 `rclone config` 更新授權。

### 安全性

- 不要將 `rclone.conf` 或包含 Token 的 `.env` 檔案提交到 Git
- 使用環境變數傳遞敏感設定
- 定期檢查授權狀態

## 故障排除

### 錯誤：RCLONE_CONF_BASE64 or RCLONE_CONF_CONTENT not set

確認已在 Zeabur 設定環境變數，並重新部署服務。

### 錯誤：exec /app/entrypoint.sh: no such file or directory

entrypoint.sh 使用了 Windows 行尾（CRLF），需轉換為 Unix 行尾（LF）：

```bash
sed -i 's/\r$//' entrypoint.sh
```

### 錯誤：Cannot connect to source/destination

1. 確認 Rclone 設定正確
2. 檢查 OAuth Token 是否過期
3. 重新執行 `rclone config` 更新授權

## 授權條款

MIT License

## 相關連結

- [Rclone 官方文件](https://rclone.org/docs/)
- [Rclone OneDrive 設定](https://rclone.org/onedrive/)
- [Rclone Google Drive 設定](https://rclone.org/drive/)
- [Zeabur 文件](https://zeabur.com/docs)
