# pave-setup

把 PAVE 助理的工具鏈一次裝好。給 sandbox 用，任何人都可以重跑。

> **給 agent：** 這個 repo 是 installer。入口在根目錄 `SKILL.md`；可先讀 `INSTALL.md` 和相關腳本。遇到權限、網絡或安全疑問時先問用戶，不要盲目執行。`AGENTS.md` 是 opt-in，沒有 `--agents` 就不會寫入。

## 用法

在 PAVE 對話貼這一行：

```
install https://github.com/cnrai/pave-transin-setup
```

agent 會 clone、安裝、驗證，然後用表格報告。要自己跑也可以：

```bash
git clone --depth 1 https://github.com/cnrai/pave-transin-setup /tmp/pave-transin-setup

# 1. 先看會做什麼，不改任何東西
bash /tmp/pave-transin-setup/install.sh --dry-run

# 2. 真的裝（預設不會寫 AGENTS.md）
bash /tmp/pave-transin-setup/install.sh

# 3. 想改全局規則才加這一步
bash /tmp/pave-transin-setup/install.sh --agents "$PWD/AGENTS.md"

# 4. 驗證
bash /tmp/pave-transin-setup/verify.sh
```

## 會裝什麼

| 項目 | 來源 | 大小 |
|---|---|---|
| `oo` | `cli.oomol.com/install.sh` | 小 |
| `composio` | `composio.dev/install --no-plugins` | 小 |
| `officecli` | `d.officecli.ai/install.sh` | 小 |
| `heygen-mcp` | 用 `skills/heygen-mcp/` 內的 package | 小 |
| `agent-browser` | `npm i -g agent-browser` + 瀏覽器 | 背景安裝 |
| Playwright + Chrome | `playwright` + Chrome/Chromium | 背景安裝 |
| 7 個 skills | 本 repo `skills/` | 小 |

`AGENTS.md` 預設**不會**寫入。它會改掉所有未來 session 的全局規則（語言、工具分流），所以要你明確加 `--agents <path>` 才會寫。先看內容：

```bash
bash install.sh --print-agents
```

選項：

```bash
bash install.sh --dry-run         # 只印會做什麼，不改任何東西
bash install.sh --print-agents    # 印出 AGENTS.md 內容就結束
bash install.sh --skills-only     # 只複製 skills
bash install.sh --no-browser      # 不裝 Playwright、Chrome、agent-browser
bash install.sh --no-network      # 跳過 remote CLI 與瀏覽器下載
bash install.sh --no-apt          # 不呼叫 apt-get
bash install.sh --force-skills    # 覆蓋已有的 skill
bash install.sh --agents <path>   # 明確指定才寫 AGENTS.md
```

Playwright、Chrome、Chromium 和 `agent-browser` 預設在背景安裝，`install.sh` 會立即返回。查進度：

```bash
bash browser-install-status.sh
```

`--with-browser` 仍可接受，但已不需要。

## 結果怎麼看

`install.sh` 最後會印一張表，每個元件一行：`ok`、`skip`、`fail`、`plan`、`running`。
有 `fail` 時 exit code 是 1。`verify.sh` 有 `MISS` 時也返回 1，兩者都可以直接用來判斷成敗。

## 憑證檢查

一條指令就掃出有沒有把 token 或個人 email 寫進 repo：

```bash
bash secret-scan.sh            # 現在的檔案
bash secret-scan.sh --history  # 所有 commit
```

它會找 JWT、`Bearer`、GitHub token、API key，以及 `oo login` 那個 `user_code`。
有 credential 就 exit 1；個人 email 只警告。

## 不會做什麼

- 不替你登入。`oo` 和 `composio` 要本人授權，裝好之後打 `/setup`。要使用 HeyGen 時，`/setup` 會請你在自己的瀏覽器登入、完成人機驗證，再把 magic link 交給 sandbox。
- 不寫任何 token 入檔案。
- 不預設改你的 `AGENTS.md`，也不改你已有的 skill（除非加 `--force-skills`）。

## 目錄

```
SKILL.md      agent 入口：說明這是 installer
skill.yaml    installer manifest
install.sh    主安裝，可重複執行
install-browser-background.sh  背景安裝 Playwright + Chrome
browser-install-status.sh      查背景安裝狀態
browser-install-wait.sh        等背景安裝完成
verify.sh     逐項檢查，印表
secret-scan.sh 掃 credential 與個人 email
INSTALL.md    給 agent 看的流程
AGENTS.md     可選的全局規則樣板
skills/       7 個 skill
```

## 7 個 skill

- `agent-browser` — 網頁要點擊、截圖、登入時用
- `heygen-mcp` — HeyGen 數位人影片
- `officecli` — `.docx` / `.xlsx` / `.pptx`
- `pave-setup` — `/setup`，兩個登入的引導
- `pw-redbook-image` — 小紅書圖文
- `seedance-2.0-superprompt` — Seedance 影片提示詞
- `seedance2-skill` — Seedance 參數參考
