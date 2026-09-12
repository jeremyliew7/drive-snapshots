![Drive Snapshots — Understand your storage](docs/banner.svg)

# Drive Snapshots

**本地磁盘清单、离线可视化，以及明确数据边界的快照对比。**

[English](README.md) · [简体中文](README.zh-CN.md) · [演示](demo/index.html) · [开发路线图](ROADMAP.md) · [参与贡献](CONTRIBUTING.md) · [Agent 指南](AGENTS.md)

Drive Snapshots 默认使用 WizTree 在 Windows 上扫描。项目保留 WizTree 原始 CSV，再把其中
的文件夹记录转换成紧凑的目录快照，供无依赖的浏览器查看器读取。路径和磁盘清单始终留在
本机。

- 使用 WizTree 管理员/MFT 模式快速扫描 NTFS 磁盘。
- 搜索目录树，通过面积图查看空间分布。
- 选择基线比较快照，并播放已导入的历史。
- 导出断网可用的单文件 HTML 报告。
- 明确区分“已测量数值”和“覆盖情况未知”。

## 运行条件

- Windows
- PowerShell 7.2 或更高版本（`pwsh`）
- 安装版或绿色版 WizTree
- 用于查看报告的现代浏览器

WizTree 是 Antibody Software 提供的第三方软件。命令行参数和 CSV 字段以
[WizTree 官方指南](https://diskanalyzer.com/guide)为准。

## 快速开始

```powershell
# 用 WizTree 扫描一个或多个磁盘或目录。
./wiztree-snapshot.ps1 -Target 'C:','D:'

# 打开 viewer/index.html，导入 snapshots/wiztree/converted/ 下的文件。

# 将选定的转换后快照打包成私有离线报告。
$files = (Get-ChildItem ./snapshots/wiztree/converted -Filter *.csv).FullName
./export-report.ps1 -Snapshot $files -Output ./reports/latest.html
```

`wiztree-snapshot.ps1` 会定位 `WizTree64.exe`，请求管理员权限以使用 MFT 快速扫描，等待
导出文件稳定，再完成转换。绿色版没有被自动找到时，显式传入路径：

```powershell
./wiztree-snapshot.ps1 -Target 'C:' -ExePath 'C:\Tools\WizTree\WizTree64.exe'
```

`-NoAdmin` 使用 WizTree 较慢的目录遍历。管理员权限可以提高 NTFS 扫描速度，但不会让扫描
成为原子快照，也不能证明所有条目都已完整记录。

如果存在 `snapshot.config.json`，命令可以复用其中的 `paths` 和全局 `maxDepth` 显示偏好：

```powershell
./wiztree-snapshot.ps1
```

## 数据流程

```text
WizTree 扫描
  -> snapshots/wiztree/raw/*.csv
  -> Convert-WizTreeCsv.ps1
  -> snapshots/wiztree/converted/*_folders.csv
  -> viewer/index.html 或 export-report.ps1
```

原始 CSV 同时包含文件和文件夹行，可能达到数百 MB。它是源证据，不要直接导入浏览器。
转换器以流式方式读取，只输出文件夹行，不会把整个原始 CSV 一次载入内存。

已有 WizTree CSV 可以直接转换，无需重新扫描：

```powershell
./Convert-WizTreeCsv.ps1 `
  -InputPath './snapshots/wiztree/raw/WizTree_20260101090000.csv' `
  -ViewDepth 5
```

WizTree 的横幅和表头会随界面语言变化。转换器按官方文档约定的固定列位置解析，不依赖中
英文表头名称。

## 快照语义

供 viewer 使用的 CSV 包含以下核心字段：

| 字段 | 含义 |
| --- | --- |
| `Depth`, `Path` | 相对导出根目录的层级，以及绝对目录路径。 |
| `SizeBytes`, `SizeGiB` | WizTree 报告的递归逻辑大小。 |
| `AllocatedBytes` | WizTree 报告的递归磁盘分配大小。 |
| `FileCount` | WizTree 报告的目录递归文件数。 |
| `DescendantDirCount` | WizTree 报告的后代目录总数。 |
| `SnapshotScope`, `ViewDepth` | 完整文件夹导出，以及 viewer 的初始显示深度。 |
| `Source` | `WizTree`。 |
| `Coverage` | `Unknown`；WizTree CSV 不提供后代读取失败向上传播的信息。 |

文件夹行保存递归汇总值，不能把父目录和子目录大小相加。某个路径缺失只表示本次没有观察
到它，不能证明已经删除。重命名会表现为旧路径未观察到、新路径被观察到。

逻辑大小与磁盘分配大小回答不同问题。viewer 的面积图与比较使用逻辑大小；转换后 CSV
同时保留分配大小，供独立分析使用。

## Viewer 与报告

打开 `viewer/index.html`，点击 **Import CSV snapshots**，选择一个或多个转换后的 CSV。
浏览器只读取用户主动选择的文件，不上传数据；再次导入会替换当前数据集。

目录树支持搜索与分页。**Levels below folder** 控制目录树和面积图的展示深度，不会修改
已导入数据。选择相同根目录的兼容快照作为基线，可以查看差异。

`export-report.ps1` 会把所选快照、CSS 和 JavaScript 嵌入一个 HTML。报告含完整本机路径
与大小，应按私有磁盘清单管理。

[演示页面](demo/index.html)只包含脚本生成的虚构数据。

## 内置扫描器

`drive-snapshot.ps1`、`initialize-snapshots.ps1` 和 `measure-snapshot-depth.ps1` 作为显式的
PowerShell 备用方案及跨平台开发入口保留，不是默认扫描路径。它们的 CSV/日志可以记录
`Unreadable` 并向祖先传播 `Incomplete`；这一覆盖模型不能与 WizTree 的
`Coverage=Unknown` 混为一谈。

## 隐私与本地数据

仓库会忽略真实快照、报告、评估、配置和生成的 HTML；只有虚构 demo 数据被允许纳入 Git。

| 位置 | 用途 |
| --- | --- |
| `snapshots/wiztree/raw/` | WizTree 原始 CSV。 |
| `snapshots/wiztree/converted/` | 供 viewer 使用的紧凑目录快照。 |
| `reports/` | 私有单文件 HTML 报告。 |
| `assessments/` | 内置扫描器的深度评估。 |
| `backups/config/` | 配置备份。 |
| `snapshot.config.json` | 当前生效的本机私有配置。 |

提交或发布前检查：

```powershell
git status --short
git ls-files
git check-ignore snapshots/wiztree/raw/example.csv reports/latest.html snapshot.config.json
```

本项目不会删除被扫描文件。目录或文件很大，不代表它适合清理。

## 开发

```powershell
./tests/wiztree.ps1
./tests/smoke.ps1
./tests/depth.ps1
node --test tests/viewer.test.cjs
./scripts/build-demo.ps1
```

WizTree 适配器和扫描入口使用 PowerShell；`viewer/` 是离线界面，`demo/` 是合成数据，
`.agents/skills/` 包含扫描、增长分析、清理规划、报告和 WizTree 导出工作流。

## 许可证

[MIT](LICENSE)。WizTree 独立分发并适用其自身许可。
