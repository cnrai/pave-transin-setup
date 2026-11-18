# INSTALL — 給 agent 看的安裝指令

用戶在對話貼了類似這一行：

```
install https://github.com/johnmak101-ops/pave-setup
```

意思是：**在這個 sandbox 裝好 PAVE 的工具鏈，然後報告**。請照下面做，不要先問問題。

## 1. 取得 repo

```bash
rm -rf /tmp/pave-setup
git clone --depth 1 https://github.com/johnmak101-ops/pave-setup /tmp/pave-setup
```

如果 `git` 不可用，退而用 curl 下載 zip，解壓到 `/tmp/pave-setup`。

## 2. 安裝

先判斷要不要裝瀏覽器。

- 用戶只說「install」→ **不要** 裝 `agent-browser`。它要下載約 300 MB 的 Chromium，屬大型依賴。
- 用戶提到要上網、截圖、登入網頁、跑了 JS 的頁面 → 問一句，得到同意才加 `--with-browser`。

```bash
bash /tmp/pave-setup/install.sh
```

如果需要瀏覽器：

```bash
bash /tmp/pave-setup/install.sh --with-browser
```

`--agents` 要指向 **PAVE 的工作區根目錄**，不是 `/tmp`：

```bash
bash /tmp/pave-setup/install.sh --agents "/你的工作區/AGENTS.md"
```

不確定工作區在哪，就用 `pwd` 的值。安裝腳本會自動備份舊的 `AGENTS.md` 成 `AGENTS.md.bak`。

## 3. 驗證

```bash
bash /tmp/pave-setup/verify.sh
```

把輸出照實回報。**`MISS` 就是沒裝好，不要說裝好了。**

## 4. 報告

用繁體中文，短句。格式：

```
裝好了。以下是現況：

| 工具 | 狀態 |
|---|---|
| oo | OK 0.x.x |
| composio | OK |
| officecli | OK |
| heygen-mcp | OK |
| agent-browser | 未裝（需要時再裝） |
| 7 個 skills | 全部 OK |
| AGENTS.md | 已寫入 <路徑> |

下一步：登入要你自己做。
1. oo — 打 /setup，或 oo login --team=<team>
2. Composio — 打 /setup，或 composio login
3. HeyGen（需要時）— 打 /setup；助理會請你在自己的瀏覽器登入並取得 magic link
```

不要在 sandbox 自動寄 HeyGen email，也不要嘗試繞過 Turnstile。不要把 email 或 magic link 寫入範例、舊對話或檔案。

## 5. 不要做的事

- 不要把 token、session token、API key 寫進任何檔案、commit 或對話。
- 不要替用戶登入。登入要本人開瀏覽器授權。
- 不要把用戶的 email 寫入安裝檔、evidence、log 或 commit。需要時即場詢問。
- 不要在安裝途中順手下載模型權重或 Chromium 以外的東西。
- 不要改 `~/.pave/skills` 內已有的 skill，除非用戶加了 `--force-skills`。
- 不要因為 `oo` 或 `composio` 沒登入就當安裝失敗。**裝好 ≠ 登入好**，分開講。

## 6. 工具分流（用戶問「你用哪個」時要這樣答）

安裝完之後，每次呼叫工具前先講一句你用哪個系統：

- 圖片、影片、PDF 理解、檔案轉換、小紅書資料、語音 → `oo`
- Gmail、Drive、Notion、Slack、WhatsApp、日曆、Sheets → `Composio`
- HeyGen 數位人 → 不是 oo 也不是 Composio，是 `heygen-mcp` skill

範例：

> 用 oo 的 `qwen.generate_image`，約 6.18 點。

不要說「用某個工具」而不講平台。兩個都可以做時：內容與媒體給 oo，帳戶資料給 Composio。

## 7. 出錯時

| 症狀 | 處理 |
|---|---|
| `oo: command not found` | 開新 shell，或 `export PATH="$HOME/.local/bin:$PATH"` |
| `composio: command not found` | `export PATH="$HOME/.composio:$HOME/.local/bin:$PATH"` |
| `heygen-mcp` 未生成 | 確認 `~/.pave/skills/heygen-mcp/package.json` 存在，再 `cd` 進去 `npm install -g .` |
| apt 要 root | 跳過瀏覽器，改用 curl；或請用戶在宿主機裝 `xvfb`、`xfonts-base` |
| 安裝腳本 exit 1 | 把 `!` 開頭的行原文貼給用戶，不要摘要成「失敗了」 |

## 8. 檔案說明

| 檔案 | 用途 |
|---|---|
| `install.sh` | 主安裝腳本，可重複執行 |
| `verify.sh` | 逐項檢查並印表 |
| `AGENTS.md` | PAVE 的全局規則，寫入工作區 |
| `skills/` | 7 個 skill，複製到 `~/.pave/skills/` |
