---
name: setup
description: 首次設定。檢查 CLI 是否齊全，帶用戶登入 oo 與 Composio；需要 HeyGen 時引導用戶在自己的瀏覽器完成登入。用在第一次對話、或工具顯示未登入時。
commands:
  - name: setup
    description: 檢查並完成 oo / Composio 登入；可選 HeyGen
---

# /setup

帶用戶完成第一次設定。一次只做一步，做完才做下一步。

## 邊界

- 不要問用戶拿密碼、token、API key。這些不可以出現在對話。
- `oo login` 印出的 device login URL 裡面有一次性的 code。它等同憑證。
- 這條 URL 只顯示一次給用戶，用完即棄。不要寫進檔案、commit、log、筆記、`AGENTS.md`，也不要貼進截圖或報告。
- 已經貼過一次就不要再重貼。要再說一次，重新執行 `oo login` 取新的。
- 不要用 `oo auth web`。它是網站登入，不是 CLI 登入。
- 不要自動執行 `/setup`。只有用戶打 `/setup`，或工具回報未登入時，才執行。
- 不要在這一步做任何付費 action。

## 步驟

先把 PATH 準備好，每個 shell 都要：

```bash
export PATH="$HOME/.local/bin:$HOME/.composio:$PATH"
```

### 1. 檢查四個 CLI

```bash
command -v oo
command -v composio
command -v officecli
command -v agent-browser
```

- 缺 `oo`：`curl -fsSL https://cli.oomol.com/install.sh | sh`
- 缺 `composio`：`curl -fsSL https://composio.dev/install | sh`
- 缺 `officecli`：`curl -fsSL https://d.officecli.ai/install.sh | bash`
- 缺 `agent-browser`：`npm i -g agent-browser && agent-browser install`

講一句每個指令做什麼，然後等它完成。不要一次過全部貼給用戶。

### 2. 登入 oo

先檢查：

```bash
oo auth status
```

已登入就記下帳號和團隊，跳去第 3 步。

未登入就**在背景**執行：

```bash
oo login
```

它會印出一條網址，然後停住等。網址的格式是：

```
https://console.oomol.com/login/device?user_code=<一次性 code>
```

`<一次性 code>` 是這次登入專用的，不可以寫入任何檔案。

做法：

1. 等背景輸出出現 `login/device` 這一行。
2. 把完整 URL 顯示給用戶**一次**，並說：「請在瀏覽器打開這條連結，完成登入。」
3. 等背景任務完成，或每 10 秒檢查一次 `oo auth status`，最多等 5 分鐘。
4. 成功後說出帳號和預設團隊。不要重貼 URL，也不要記下 code。

如果 20 秒內沒有出現 URL，顯示最後幾行輸出，停止，不要重試第二次。

### 3. 登入 Composio

先檢查：

```bash
composio whoami
```

已登入就跳去第 4 步。

未登入：

```bash
composio login --no-wait --no-skill-install
```

它會印出一條 `dashboard.composio.dev/?cliKey=...` 的 URL，然後即刻返回。

1. 把 URL 顯示給用戶，說：「請在瀏覽器打開，登入你的 Composio 帳號。」
2. 在背景執行，最多等 10 分鐘：

   ```bash
   composio login --poll
   ```

3. 用 `composio whoami` 確認。

如果 `--poll` 超時，叫用戶再打開一次 URL，然後再跑 `--poll` 一次。不要叫他貼 key。

### 4. 可選：HeyGen

只在用戶要使用 HeyGen 時才做。

先請用戶自己在瀏覽器登入，不要把 email 交給 agent 代寄：

1. 開 `https://app.heygen.com`，最好用無痕視窗。
2. 點 `Use email`，由用戶自己輸入 email。
3. 按一次 `Send a secure magic link`。
4. `Verify you are human` 由用戶自己完成。
5. 開最新一封 HeyGen email，右鍵按鈕，選 `Copy link address`，不要直接點開。
6. 把連結貼回對話。

規則：

- 不要在 sandbox 自動送 email。
- 不要嘗試處理或繞過 Turnstile。
- 不要把 email 寫入檔案、log 或 commit。
- 如果 `heygen-mcp` 或 `agent-browser` 未安裝，先說未安裝。不要為此下載 Chromium。
- 已安裝就按 `heygen-mcp` skill 的 user-owned magic-link 流程登入。

### 5. 可選：Google Drive

只在用戶要求「檔案要保存」或「要給人」時才做。

```bash
composio search "upload a file to Google Drive"
```

用搜尋結果的 toolkit slug，然後：

```bash
composio link <slug>
```

同樣是顯示 URL、用戶在瀏覽器授權、agent 等完成。不要自己編 slug。

### 6. 免費 smoke test

```bash
oo search "qwen image"
composio search "list files" --limit 3
```

兩個都返回結果，代表登入和網絡都正常。這兩個搜尋不收費。

### 7. 回報

用一個小表總結：

| 項目 | 狀態 |
|---|---|
| oo | 已登入 / `<帳號>` / team `<team>` |
| Composio | 已登入 / `<帳號>` |
| HeyGen | 已登入 / 未登入 / 不需要 |
| officecli | `<版本>` |
| agent-browser | `<版本>` / Chromium 已安裝 |
| Google Drive | 已連接 / 未連接 / 不需要 |

最後說一句：「設定完成。你可以開始用，例如叫我做一份小紅書圖文，或讀一份 PDF。」

## 失敗處理

- 指令不存在：回到第 1 步，裝缺少的那個。
- 登入 URL 沒有出現：顯示原始錯誤，停止。
- 登入超時：叫用戶重新開 URL，再試一次 `--poll`；仍然失敗就停，不要無限重試。
- 網絡錯誤：重試一次，然後回報。
- 不要在失敗時假裝成功。
