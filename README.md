# pave-setup

把 PAVE 助理的工具鏈一次裝好。給 sandbox 用，任何人都可以重跑。

## 用法

在 PAVE 對話貼這一行：

```
install https://github.com/johnmak101-ops/pave-setup
```

agent 會 clone、安裝、驗證，然後用表格報告。要自己跑也可以：

```bash
git clone --depth 1 https://github.com/johnmak101-ops/pave-setup /tmp/pave-setup
bash /tmp/pave-setup/install.sh --agents "$PWD/AGENTS.md"
bash /tmp/pave-setup/verify.sh
```

## 會裝什麼

| 項目 | 來源 | 大小 |
|---|---|---|
| `oo` | `cli.oomol.com/install.sh` | 小 |
| `composio` | `composio.dev/install --no-plugins` | 小 |
| `officecli` | `d.officecli.ai/install.sh` | 小 |
| `heygen-mcp` | 用 `skills/heygen-mcp/` 內的 package | 小 |
| `agent-browser` | `npm i -g agent-browser` + Chromium | **約 300 MB，預設不裝** |
| 7 個 skills | 本 repo `skills/` | 小 |
| `AGENTS.md` | 本 repo 根目錄 | 小 |

選項：

```bash
bash install.sh --skills-only      # 只複製 skills 和 AGENTS.md
bash install.sh --with-browser     # 連 Chromium 一齊裝
bash install.sh --no-apt           # 不呼叫 apt-get
bash install.sh --force-skills     # 覆蓋已有的 skill
bash install.sh --agents <path>    # 指定 AGENTS.md 位置
```

## 不會做什麼

- 不替你登入。`oo` 和 `composio` 要本人授權，裝好之後打 `/setup`。要使用 HeyGen 時，`/setup` 會先問你的 HeyGen 帳號 email，再由你完成 magic link。
- 不寫任何 token 入檔案。
- 不改你已有的 skill（除非加 `--force-skills`）。

## 目錄

```
install.sh    主安裝，可重複執行
verify.sh     逐項檢查，印表
INSTALL.md    給 agent 看的流程
AGENTS.md     全局規則，寫入工作區根目錄
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
