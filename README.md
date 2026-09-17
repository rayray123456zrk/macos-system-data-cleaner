# macOS System Data Cleaner

中文 | [English](#english)

一个安全优先的 Codex Skill，用于诊断 macOS 中异常膨胀的“系统数据”，识别真正可清理的缓存，并在用户明确授权后执行可恢复的清理。

> **核心原则：先扫描、再分类、后清理。默认只读；清理时优先移入废纸篓。**

## 为什么需要它？

macOS“系统设置 → 通用 → 储存空间”里的“系统数据”并不只代表操作系统文件。它可能混合显示：

- 应用缓存、日志和更新残留；
- `Application Support` 与应用容器数据；
- 浏览器、本地 AI 和语音识别模型；
- 开发工具缓存、SDK 与模拟器数据；
- APFS 或 Time Machine 本地快照；
- 聊天附件、游戏和数据库等真实用户数据。

这个 Skill 会先测量和解释占用，再将目标分成不同风险等级，避免把用户数据误当缓存删除。

## 功能

- 检查 Data 卷的真实磁盘压力，而不是只读取 macOS 的分类数字；
- 检查 Time Machine 本地快照；
- 分析 `~/Library`、`/private/var`、`/Library/Updates` 和常见隐藏缓存；
- 区分普通缓存、可重新下载的大型模型，以及不可随意删除的用户数据；
- 提供精确路径、实测大小、删除影响和预计可回收空间；
- 清理前再次确认目标，默认移动到带日期的废纸篓目录；
- 清理后验证源目录、废纸篓大小和磁盘状态；
- 对管理员权限、永久删除和正在使用的运行环境设置明确保护。

## 安全设计

| 类型 | 默认处理方式 |
| --- | --- |
| 下载缓存、日志、临时文件、旧更新包 | 可建议清理，获得授权后移入废纸篓 |
| 本地 AI 模型、语音模型、SDK、开发运行环境 | 说明重新下载或离线功能影响后再决定 |
| 聊天附件、邮件、数据库、游戏、浏览器配置 | 视为用户数据，优先使用应用内存储管理 |
| 系统所有目录或永久删除 | 单独请求明确授权，并严格限定路径 |

Skill 不会因为用户说“检查”或“分析”就自动删除文件，也不会把 `/Library/Updates` 之类的目标扩大成整个 `/Library`。

## 安装

将 Skill 克隆到 Codex Skills 目录：

```bash
git clone https://github.com/rayray123456zrk/macos-system-data-cleaner.git /tmp/macos-system-data-cleaner
mkdir -p ~/.codex/skills
cp -R /tmp/macos-system-data-cleaner/macos-system-data-cleaner ~/.codex/skills/
```

重新打开 Codex 会话后即可使用。也可以仅下载仓库中的 `macos-system-data-cleaner` 文件夹，并将其放入 `~/.codex/skills/`。

## 使用示例

```text
使用 $macos-system-data-cleaner 检查为什么我的系统数据占了 100GB，先不要删除任何文件。
```

```text
使用 $macos-system-data-cleaner 清理刚才确认的低风险缓存，全部先移到废纸篓。
```

```text
使用 $macos-system-data-cleaner 找出本地 AI 模型和开发工具缓存，并说明删除后的影响。
```

## 独立运行只读审计脚本

脚本只读取磁盘使用情况，不会删除或移动文件：

```bash
zsh macos-system-data-cleaner/scripts/audit_macos_storage.sh
```

部分 macOS 目录受到隐私保护，因此出现权限提示或无法读取某些目录并不代表脚本失败。

## 项目结构

```text
macos-system-data-cleaner/
├── SKILL.md
├── agents/
│   └── openai.yaml
└── scripts/
    └── audit_macos_storage.sh
```

## 重要提示

- 移入废纸篓不会立即释放空间，只有清空废纸篓后空间才会真正回收。
- 缓存和模型可能被应用重新创建或下载。
- 清理前请退出相关应用，以降低文件正在写入或立即重建的风险。
- 请先备份重要数据。本项目不提供数据恢复保证。

---

<a id="english"></a>

## English

A safety-first Codex Skill for diagnosing unexpectedly large macOS “System Data,” identifying genuinely removable caches, and performing recoverable cleanup only after explicit user authorization.

> **Core principle: audit first, classify second, clean last. Read-only by default; move items to Trash before permanent deletion.**

## Why this skill?

The “System Data” category in macOS Storage Settings does not contain only operating-system files. It may also include:

- application caches, logs, and updater remnants;
- Application Support and sandbox container data;
- browser, local AI, and speech-recognition models;
- developer caches, SDKs, and simulator data;
- APFS or Time Machine local snapshots;
- genuine user data such as chat attachments, games, and databases.

This skill measures and explains storage usage first, then separates cleanup candidates by risk so that user data is not mistaken for disposable cache.

## Features

- Measures actual pressure on the writable Data volume;
- checks Time Machine local snapshots;
- analyzes `~/Library`, `/private/var`, `/Library/Updates`, and common hidden caches;
- separates ordinary cache, expensive-to-redownload models, and user data;
- reports exact paths, measured sizes, consequences, and estimated recoverable space;
- revalidates every target and uses a dated Trash folder by default;
- verifies source paths, Trash contents, and disk state after cleanup;
- protects administrator-owned paths, permanent deletion, and active runtimes.

## Safety model

| Category | Default behavior |
| --- | --- |
| Download caches, logs, temporary files, updater remnants | Recommend cleanup; move to Trash after authorization |
| Local AI models, speech models, SDKs, runtimes | Explain redownload and offline-use impact before removal |
| Chat media, mail, databases, games, browser profiles | Treat as user data; prefer the app's own storage manager |
| System-owned paths or permanent deletion | Request separate explicit authorization and keep the path narrow |

The skill never treats a request to “inspect” or “diagnose” as permission to delete. It also prevents a narrow target such as `/Library/Updates` from expanding into `/Library`.

## Installation

Clone the repository and copy the skill into the Codex Skills directory:

```bash
git clone https://github.com/rayray123456zrk/macos-system-data-cleaner.git /tmp/macos-system-data-cleaner
mkdir -p ~/.codex/skills
cp -R /tmp/macos-system-data-cleaner/macos-system-data-cleaner ~/.codex/skills/
```

Start a new Codex session after installation. You can also download only the `macos-system-data-cleaner` folder and place it under `~/.codex/skills/`.

## Usage examples

```text
Use $macos-system-data-cleaner to find out why System Data uses 100 GB. Do not delete anything yet.
```

```text
Use $macos-system-data-cleaner to clean the low-risk caches we confirmed. Move everything to Trash first.
```

```text
Use $macos-system-data-cleaner to identify local AI models and developer caches, and explain the impact of removing them.
```

## Run the read-only audit script directly

The bundled script reads storage usage only. It does not move or delete files:

```bash
zsh macos-system-data-cleaner/scripts/audit_macos_storage.sh
```

Some macOS directories are privacy-protected, so permission warnings or unavailable paths do not necessarily mean the audit failed.

## Repository structure

```text
macos-system-data-cleaner/
├── SKILL.md
├── agents/
│   └── openai.yaml
└── scripts/
    └── audit_macos_storage.sh
```

## Important notes

- Moving files to Trash does not immediately free disk space. Space is reclaimed only after Trash is emptied.
- Applications may recreate or redownload caches and models.
- Quit affected applications before cleanup to reduce the risk of active writes or immediate regeneration.
- Back up important data first. This project does not guarantee data recovery.

## License

No license has been granted yet. All rights are reserved unless a license file is added later.
