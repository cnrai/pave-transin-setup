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

瀏覽器安裝已改成 **背景執行**。`install.sh` 會強制啟動 Playwright + Chrome 安裝，但不等待下載完成。

```bash
bash /tmp/pave-setup/install.sh --agents "/你的工作區/AGENTS.md"
```

`--agents` 要指向 **PAVE 的工作區根目錄**，不是 `/tmp`。不確定工作區在哪，就用 `pwd` 的值。安裝腳本會自動備份舊的 `AGENTS.md` 成 `AGENTS.md.bak`。

只在用戶明確說不要瀏覽器時才加：

```bash
bash /tmp/pave-setup/install.sh --no-browser
```

### 2.1 立刻開子 session 監控

`install.sh` 返回後，主 session 要立即做兩件事：

1. 告訴用戶：CLI 已處理，Playwright + Chrome 正在背景安裝。
2. **開一個背景子 session 專門監控**，不要讓主對話等 npm 或 Chrome 下載。

子 session 的責任：

```bash
bash /tmp/pave-setup/browser-install-status.sh
```

- 每 20-30 秒讀一次狀態。
- `state=running` 或 `state=starting`：繼續等。
- `state=done`：回報 Playwright + Chrome 完成。
- `state=partial`：回報哪一個瀏覽器元件失敗。
- `state=failed`：讀 `~/.pave/browser-install/install.log` 最後 40 行，回報真正錯誤。
- 最多等 30 分鐘；不要無限重試。
- 子 session 完成後把結果回給主 session，由主 session 向用戶總結。

不要在主 session 同步等待這個背景工作。

## 3. 驗證

```bash
bash /tmp/pave-setup/verify.sh
```

把輸出照實回報。**`MISS` 就是沒裝好，不要說裝好了。**
瀏覽器若顯示 `WAIT`，代表背景安裝仍在進行，不是失敗。

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
| agent-browser | OK / 背景安裝中 |
| Playwright + Chrome | 背景安裝中 / OK / partial |
| 7 個 skills | 全部 OK |
| AGENTS.md | 已寫入 <路徑> |

Playwright + Chrome 的下載由背景子 session 監控；主對話先繼續。

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
- 不要在主 session 同步等待 Playwright、Chrome 或 agent-browser 下載。
- 只允許背景安裝 Playwright、Chrome、Chromium 與 agent-browser；不要順手下載模型權重或其他大型依賴。
- 背景安裝失敗時，把真正的 log 錯誤貼給用戶；不要假裝完成。
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
| `install-browser-background.sh` | 背景安裝 Playwright、Chrome、Chromium、agent-browser |
| `browser-install-status.sh` | 查詢背景瀏覽器安裝狀態與最近 log |
| `verify.sh` | 逐項檢查並印表 |
| `AGENTS.md` | PAVE 的全局規則，寫入工作區 |
| `skills/` | 7 個 skill，複製到 `~/.pave/skills/` |
