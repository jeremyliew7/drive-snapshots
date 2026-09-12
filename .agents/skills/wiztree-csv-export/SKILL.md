---
name: wiztree-csv-export
description: 用 WizTree 命令行导出磁盘全量数据 CSV（整个驱动器或指定文件夹），可选管理员 MFT 快速扫描与全部扩展列，并在导出后校验文件完整性。当用户要生成 WizTree CSV、导出整盘文件清单、做磁盘占用分析/清理前的全量扫描时使用。Triggers - wiztree csv, wiztree export, full disk scan, 导出磁盘 CSV, 磁盘全量扫描, 生成文件清单.
when-to-use: 用户提到 WizTree、磁盘全量扫描、导出磁盘文件清单/CSV、分析某个盘的文件占用、清理磁盘前的快照.
allowed-tools: run_terminal_command, read_file, grep
argument-hint: [盘符或文件夹，如 C: 或 D: 或 "C:\Users"]
compatibility: Windows；需要已安装 WizTree（安装版或绿色版）；/admin=1 的 MFT 扫描需要管理员权限
---

# WizTree 磁盘全量数据 CSV 导出

用 WizTree 的命令行 `/export` 参数扫描一个驱动器或文件夹，把扫描结果导出为 CSV，
用于后续的磁盘占用分析、清理决策或归档快照。

## 快速使用

脚本路径：`.agents/skills/wiztree-csv-export/scripts/Export-WizTreeCsv.ps1`
（`.grok/skills` 是指向 `.agents/skills` 的目录联接，两个路径等价。下面的示例按项目根目录相对路径书写。）

本项目的默认快照命令（导出原始 CSV，并生成 viewer 可读的目录快照）：

```powershell
./wiztree-snapshot.ps1 -Target 'C:','D:'
```

原始 CSV 保存到 `snapshots/wiztree/raw/`，流式转换后的目录 CSV 保存到
`snapshots/wiztree/converted/`。viewer 和 `export-report.ps1` 使用 converted 文件；
不要把数百 MB 的逐文件 raw CSV 直接导入浏览器。

仅调用 WizTree 导出器：

```powershell
& ".agents/skills/wiztree-csv-export/scripts/Export-WizTreeCsv.ps1" -Target 'C:' -OutDir .
```

常用变体：

```powershell
# 不做 MFT 扫描（不提权，速度慢很多，且没有有效的 MFT 记录号）
& "<skill>\scripts\Export-WizTreeCsv.ps1" -Target 'D:' -NoAdmin

# 只要基础列（文件名称,大小,分配,修改时间,属性,文件,文件夹）
& "<skill>\scripts\Export-WizTreeCsv.ps1" -Target 'C:' -Minimal

# 只导出某种类型的文件，并同时生成"文件类型汇总"CSV
& "<skill>\scripts\Export-WizTreeCsv.ps1" -Target 'C:' -Filter '*.mp3|*.wav' -FileTypes

# 多盘一次性导出
& "<skill>\scripts\Export-WizTreeCsv.ps1" -Target 'C:', 'D:'
```

脚本会：定位 `WizTree64.exe` → 需要时通过 UAC 提权运行 → 等待进程真正结束 →
确认 CSV 已写入且大小稳定 → 打印表头、行数、文件总字节数、最大的若干文件。

## 直接调用 WizTree（脚本不适用时）

```powershell
$exe = 'C:\Tools\WizTree\WizTree64.exe'   # 安装位置可用注册表 Uninstall 项的 InstallLocation 查到
Start-Process -FilePath $exe -Wait -ArgumentList @(
    '"C:"',
    '/export="C:\temp\cdrive.csv"',
    '/admin=1',
    '/exportfolders=1', '/exportfiles=1', '/sortby=1'
)
```

命令行完整形式（64 位 Windows 用 `WizTree64.exe`）：

```
WizTree64.exe "drive/folder" /export="filename" [/filter="filespec"] [/filterexclude="filespec"]
   [/filterfullpath=0|1] [/admin=0|1] [/exportfolders=0|1] [/exportfiles=0|1] [/sortby=sortoption]
   [/exportmftrecno=0|1] [/exportUTCTime=0|1]
   [/exportalldates=1] [/exportallsizes=1] [/exportsplitfilename=1] [/exportdrivecapacity=1]
   [/exportpercentofparent=1] [/exportmaxdepth=n]
WizTree64.exe "drive/folder" /exportfiletypes="filename" [/admin=0|1] [...]
WizTree64.exe C: /treemapimagefile="C:\temp\image_%d.png" [/treemapimagewidth=1024] [/treemapimageheight=768]
```

要点：

| 参数 | 说明 |
| --- | --- |
| `/admin=1` | 管理员模式，启用 MFT 直接扫描（快得多）。未提权时会弹 UAC |
| `/exportfolders=0` / `/exportfiles=0` | 关闭文件夹行 / 文件行；默认两者都导出 |
| `/sortby` | `0` 名称（默认）、`1` 大小降序、`2` 分配大小降序、`3` 修改时间降序 |
| `/exportmftrecno=1` | 增加 MFT 记录号，可当唯一文件 ID；仅在整个 NTFS 盘 + 管理员模式下有效 |
| `/exportUTCTime=1` | 时间用 UTC（NTFS 内部时间），默认本地时间 |
| `/exportalldates=1` | 增加最后访问时间、创建时间 |
| `/exportallsizes=1` | 增加文件夹自身（不含子文件夹）的总大小与分配大小 |
| `/exportsplitfilename=1` | 把根、目录、文件名、扩展名拆成独立列 |
| `/exportdrivecapacity=1` | 增加磁盘容量/剩余/已用/保留（只写在第一条记录上） |
| `/exportpercentofparent=1` | 增加"占父目录百分比" |
| `/exportmaxdepth=n` | 限制导出目录深度，默认 0 = 不限 |
| `/filter` / `/filterexclude` | 只导出/排除匹配项。`|` 是 OR，空格是 AND；可用 `*` `?` 通配 |

排错与陷阱：

- **必须等待进程结束。** 32 位的 `wiztree.exe` 会自动拉起 `wiztree64.exe` 后立刻返回；
  批处理里要用 `start /wait`，PowerShell 里要 `Start-Process -Wait`，否则会读到还没写完的 CSV。
- **提权后父进程会先退出。** 用 `/admin=1` 且当前未提权时，WizTree 重新以管理员启动自己，
  原进程立即结束；脚本因此改为直接等"文件大小连续两次不变"而不是只等进程。
- **`%d` / `%t`** 在文件名里替换为 `YYYYMMDD` / `HHMMSS`。写在 `.bat`/`.cmd` 里要写成 `%%d` / `%%t`。
- **含空格的过滤条件**用单引号代表双引号，避免空格被当成 AND：
  `/filter="'C:\Program Files\'|'C:\Program Files (x86)\'"`
- **排除过滤在扫描阶段生效**，对超大磁盘能显著缩短扫描时间。
- 未提权时 WizTree 退化为遍历目录，速度慢很多，且 MFT 记录号不可用。
- WizTree 的界面语言会影响 CSV 横幅与表头。解析器必须兼容中文、英文和其他本地化名称。

## CSV 结构（解析前必读）

导出文件是 **UTF-8 带 BOM**。真正的数据从第 3 行开始：

1. 第 1 行：横幅，形如 `生成由 WizTree 4.32 2026/9/12 0:43:18 (您可以通过捐赠隐藏此信息)`——随界面语言变化。
2. 第 2 行：列名，**同样随语言本地化**（中文示例：`文件名称,大小,分配,修改时间,属性,文件,文件夹,...`）。
3. 第 3 行起：数据。文件夹行在最后，或按 `/sortby` 混排。

**列名会本地化，所以按位置解析列，不要按表头名字匹配。** 打开扩展参数后列顺序固定为：

| 序号 | 列 | 含义 |
| --- | --- | --- |
| 0 | 文件名称 | 完整路径；文件夹行以 `\` 结尾 |
| 1 | 大小 | 文件行=该文件；文件夹行=含子项的总大小 |
| 2 | 分配 | 分配的磁盘空间；**以 0 开头表示硬链接**，不占额外空间 |
| 3 | 修改时间 | `yyyy/mm/dd HH:mm:ss`，默认本地时间 |
| 4 | 属性 | 位标志之和：1=只读 2=隐藏 4=系统 32=归档 2048=压缩 |
| 5–6 | 文件 / 文件夹 | 该文件夹内的文件数、文件夹数（仅文件夹行有意义） |
| 7–8 | MFTRECNO / MFTPARENTRECNO | `/exportmftrecno=1`：MFT 记录号与父记录号 |
| 9–10 | LASTACCESSDATE / CREATEDDATE | `/exportalldates=1` |
| 11–12 | FOLDERSIZE / FOLDERALLOCATED | `/exportallsizes=1`：文件夹自身大小，不含子文件夹 |
| 13–16 | ROOT / FOLDERNAME / FILENAME / FILEEXT | `/exportsplitfilename=1` |
| 17 | PERCENTOFPARENT | `/exportpercentofparent=1` |
| 末尾 4 列 | DRIVECAPACITY / FREESPACE / USEDSPACE / RESERVEDSPACE | 始终存在且在最后，但**只有第一条数据记录有值**。开满扩展参数时是 18–21，只导基础列时是 7–10 |

不加任何扩展参数时，列就是基础 7 列（0–6）后面直接跟容量四列（7–10）。
扩展布局与基础布局的容量列位置不同，因此解析器从行尾读取容量四列，不固定使用
18–21 等绝对列号。

统计磁盘占用时的规则：

- **只累加文件行**，文件夹行是汇总值，一起加会重复计数。
- 跳过分配列以 `0` 开头的硬链接行，它们不占额外空间。
- 用第一条数据记录末尾四列（容量/剩余/已用/保留）交叉验证累加结果；整盘导出时该行就是盘根行。
- 中文/英文列名都可能出现，脚本里的 `scripts/` 若是新增解析代码，请沿用位置解析。

## 验证导出是否成功

1. 文件存在且大小远大于 0（整盘 CSV 通常几十到几百 MB）。
2. 第 1 行是 WizTree 横幅，且其中的版本号/日期与本次运行相符。
3. 第一行数据是盘根行（如 `"C:\",...`），且该行带有容量列。
4. 行数在合理范围（文件行数 + 文件夹行数），不是几行就结束。
5. 抽查最大文件是否与 `Get-ChildItem` 或资源管理器观察到的一致。

## 本仓库的转换入口

`Convert-WizTreeCsv.ps1` 按位置解析本地化列名，流式筛选文件夹行，并输出 Drive Snapshots
目录 CSV。转换结果保留逻辑大小、分配大小、递归文件数和来源标记。WizTree CSV 没有可与
内置扫描器 `Incomplete` 等价的读取失败传播信息，因此转换结果把 `Coverage` 标成
`Unknown`；不要把它解释为已证明完整。
