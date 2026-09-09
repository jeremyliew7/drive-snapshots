![Drive Snapshots — Understand your storage, over time](docs/banner.svg)

# Drive Snapshots

**只读磁盘快照，离线可视化，看清空间去了哪里、发生了什么变化。**

[English](README.md) · [简体中文](README.zh-CN.md) · [演示](demo/index.html) · [参与贡献](CONTRIBUTING.md) · [Agent 指南](AGENTS.md)

用 PowerShell 记录目录大小，在浏览器中查看和对比。无需账户、云服务或运行时依赖，文件清单留在本机。

- 初始化选择多个扫描盘或目录、输出位置和报告深度。
- 搜索目录树，通过面积图逐层查看空间分布。
- 选择基线、切换历史快照、播放变化。
- 导出嵌入数据与样式的单文件 HTML，断网也能打开。
- 提供快照生成、增长分析、清理规划和报告生成的 agent skills。

## 先看演示

下载项目，直接打开 **[demo/index.html](demo/index.html)**。四个虚构快照展示项目增长、新目录和下载目录消失等情况，数据全部来自 [生成脚本](scripts/build-demo.ps1)，不使用任何真实磁盘数据。GitHub 中点击 HTML 会显示源代码，需要下载打开；也可以只将 `demo/` 发布到 GitHub Pages。

## 快速开始

需要 **PowerShell 7.2+**（`pwsh`），不支持 Windows PowerShell 5.1。本地主要在 Windows 验证，CI 配置覆盖 Windows、Linux 和 macOS。查看器只需要现代浏览器。

```powershell
# 选择扫描根目录、输出目录和详细程度，评估并保存各盘默认深度。
./initialize-snapshots.ps1

# 按保存的设置扫描；隔一段时间再执行一次。
./drive-snapshot.ps1

# 将快照打包为独立 HTML。
$files = (Get-ChildItem ./snapshots -Recurse -Filter *.csv).FullName
./export-report.ps1 -Snapshot $files -Output ./reports/latest.html
```

打开 `reports/latest.html` 查看。也可以打开 `viewer/index.html`，点击 **Import CSV snapshots** 一次选择多个 CSV。每次导入替换当前数据集。已导出的报告和 demo 可直接在浏览器再次导出；未打包查看器的浏览器导出需要 HTTP，因为浏览器限制 `file://` 读取外部资源。PowerShell 导出不受此限制。

## 配置

初始化生成被 Git 忽略的 `snapshot.config.json`，不会覆盖已有配置。之后直接编辑；格式见 [配置示例](snapshot.config.example.json)。

```powershell
# 无交互初始化；替换为自己的目录。
./initialize-snapshots.ps1 -Path 'C:\Users\Public','D:\Projects' -OutDirRoot 'D:\Snapshots' -MaxDepth 4

# 临时参数优先于配置文件。
./drive-snapshot.ps1 -Path 'D:\Projects' -MaxDepth 3

# 使用其他配置。
./drive-snapshot.ps1 -Config ./snapshot.local.json
```

| 配置 / 参数 | 含义 |
| --- | --- |
| `paths` / `-Path` | 一个或多个盘根目录或文件夹，无本机专属默认值。 |
| `outputDirectory` / `-OutDirRoot` | 默认是配置文件旁的 `snapshots`。 |
| `maxDepth` / `-MaxDepth` | 全局回退值默认 5 层；命令行显式值覆盖各盘默认值。0 表示仅根目录。 |
| `maxDepthByPath` | 初始化按扫描根目录保存的默认深度，优先于全局回退值。 |
| `-Config` | 配置文件位置；相对扫描路径和输出路径均以此文件目录为基准。 |

深度限制的是**输出行数**，扫描仍遍历整个子树，才能得到递归总大小。每个扫描根目录使用名称加路径哈希分组，以时间戳保留历史。扫描排除配置的输出目录；比较时应保持输出目录和扫描范围一致。

## 正确理解数据

UTF-8 日志包含对齐的扫描摘要、UTC 起止时间和耗时、磁盘容量、最大的 30 个一级目录，以及带编号的读取失败明细。大小使用 GiB 和精确字节数，磁盘分配空间与扫描到的逻辑大小分开展示。`PARTIAL` 表示下界，`OK` 仅表示没有记录到读取错误，不保证原子完整性。目录路径完整保留，不被表格截断。历史日志不会被改写。

| CSV 字段 | 含义 |
| --- | --- |
| `Depth` / `Path` | 根目录深度为 0，路径为绝对目录路径。 |
| `SizeBytes` / `SizeGiB` | 递归逻辑大小；GiB = 2³⁰ 字节。 |
| `FileCount` | 递归统计实际观察到的普通文件数量。 |
| `DirCount` | 直接子目录数，包含被跳过的目录链接。 |
| `Reparse` | 目录链接或联接点，记录但不跟随。 |
| `Unreadable` | 此目录遇到读取失败。 |
| `Incomplete` | 此目录或后代读取失败，新增字段。 |

扫描不会自动提权或修改被扫描文件，只写 CSV、日志和初始化配置。跳过文件链接，不跟随目录链接，扫描根目录不能是链接。硬链接可能重复计数，压缩文件和稀疏文件按逻辑大小计量，不代表真实分配空间。扫描也不是原子快照，期间文件可能变化。

读取失败时大小只是**下界**。旧 CSV 没有向上传递的 `Incomplete` 标记。查看器仅允许根目录和最大已观察深度相同的快照比较；旧格式缺少完整扫描参数，仍需自行确保筛选与权限一致。路径消失表示“未观察到”，不代表证实删除；重命名表现为旧路径消失、新路径出现。不要将父目录与子目录递归大小相加。

面积图展示当前目录的直接子目录，以及直接文件/未报告明细。变化表最多展示 50 个直接子目录；直接文件变化会反映在总大小中。历史按文件名排序并默认选最新，建议保留时间戳文件名。播放是已导入历史的回放，不是实时监视磁盘；重新扫描后需重新导入或生成报告。目录列表最多显示 1,500 个匹配项，可搜索缩小范围。扫描内存随目录数量增长，超大报告在浏览器中可能变慢。

## 隐私与发布

`.gitignore` 排除本地 CSV、日志、`snapshots/`、`reports/`、本机配置、生成 HTML 和旧式单字母盘目录，仅允许合成 demo 的数据及页面进入 Git。自定义配置、报告或 JSON 导出名称需要增加相应规则；忽略规则不会移除已经跟踪的文件。

报告包含完整路径与大小，分享报告即分享这些清单。公共演示请**只发布 `demo/`**，不要公开托管真实快照目录。

```powershell
git status --short
git ls-files
git check-ignore snapshots/example.csv snapshot.config.json reports/latest.html
```

## 开发与 agents

```powershell
./tests/smoke.ps1
node --test tests/viewer.test.cjs
./scripts/build-demo.ps1
```

Node 仅用于开发阶段解析器测试。根目录包含扫描器与导出器，`viewer/` 是浏览器源码，`demo/` 是合成数据，`.agents/skills/` 提供快照生成、增长分析、清理规划和报告生成工作流。详见 [AGENTS.md](AGENTS.md) 和 [CONTRIBUTING.md](CONTRIBUTING.md)。

后续可以增加快照元数据、更严格的可比性校验、扩展名汇总、历史曲线和应用专属清理适配。当前项目不删除文件，也不把“大目录”等同于“可清理”。

## 许可证

[MIT](LICENSE)，欢迎贡献。

## 系统盘权限与不完整扫描

Windows 可显式请求 UAC 管理员权限：

```powershell
./drive-snapshot.ps1 -Path 'C:\' -Elevate
```

默认不会自动提权。取消 UAC 或提权子进程失败会报错，不会显示扫描成功。管理员权限通常能改善覆盖，但 SYSTEM 专属、锁定或扫描中变化的资源仍可能不可读。其他系统可使用适当权限启动 `pwsh`；`-Elevate` 仅支持 Windows。

读取失败时，脚本会立即在扫描结束输出警告，在日志记录失败路径，给对应目录标记 `Unreadable`，并将 `Incomplete` 向所有祖先传递——即使失败目录超出报告深度也不遗漏。页面会突出显示部分覆盖，提示差异可能来自权限变化。比较系统盘时应保持提权状态一致，并检查两次日志；不可访问的数据不会被猜测补齐。

## 评估每个磁盘适合的报告深度

```powershell
# Windows：评估当前用户可见的所有已就绪固定磁盘。
$assessment = ./measure-snapshot-depth.ps1
$assessment | Format-Table Path,RecommendedMaxDepth,RecommendedRows,RecommendationBasis,Confidence
# 查看每加深一层的目录数量变化。
$assessment | ForEach-Object { $_.Path; $_.DepthRows | Format-Table }

# 显式指定目录，也支持 Linux/macOS。
./measure-snapshot-depth.ps1 -Path 'D:\Projects' -TargetRows 50000
# 保留原先仅按行数预算选择最深完整层的模式。
./measure-snapshot-depth.ps1 -Path 'D:\Projects' -Strategy Budget
```

默认 `Growth` 策略逐层比较累计目录数。`AddedRows` 表示本层新增行数，`GrowthRatio` 表示本层累计行数除以上层累计行数。首次同时满足**新增至少 5,000 行、累计行数达到前一层 3 倍**的完整层级，会被选为建议深度。推荐包含这次首次大量展开，保留有用明细，而不是退回它之前的浅层。阈值可用 `-MinAddedRows`、`-GrowthFactor` 调整。这是可解释的启发式判断，不证明深度最优，也不衡量文件清理价值；不依赖固定盘符规则。

没有发现符合条件的增长点时，回退到预算内最深的完整层级；`-Strategy Budget` 始终使用这一回退规则。默认每个根目录的探查上限为 **50,000 行、12 层、500,000 个条目、20 秒**。1,500 行适合紧凑探查，200,000 行允许更详细探索。行数预算限制探查范围，不要求最终推荐达到这个数量。未探查完整的层不能作为增长点；增大预算可能揭示此前未看到的增长。文件消耗条目预算，但只有目录计入报告行数。预算在文件系统操作之间检查，单次阻塞操作可能超时。

`DepthRows` 保存深度、新增行数、累计行数、增长倍数、是否完成枚举及增长点标记。未完成层的行数只是下界。`RecommendedRows` 是建议深度的目录数，`ObservedRows` 可能包含更深层的部分结果；`RecommendationBasis` 解释推荐原因，`StopReason` 解释探查为何结束。`LevelComplete` 仅表示完成该层枚举流程，不保证所有目录可读。权限失败或时间/条目限制会标记 `Low`，根目录不可读时不提供建议并标记 `Unavailable`；`Observed` 也只代表可见目录。不会读取文件内容或跟随链接。

Windows 自动发现只包含已就绪固定磁盘，其他路径需显式传入；其他平台必须指定 `-Path`。需要提升覆盖范围时，在管理员 PowerShell 评估，脚本不自动提权或修改 ACL。应保持评估与正式扫描的权限和排除范围一致。

结果默认保存到被 Git 忽略的 `reports/depth-assessment.json`，`-Output ''` 可关闭写入。默认排除脚本旁的 `snapshots/` 和 `reports/`，自定义位置可用 `-ExcludePath`。单独评估不修改配置；`maxDepth` 仍只限制报告明细，不缩短正式扫描的完整遍历。

### 用户与 agent 的统一首次初始化

运行 `./initialize-snapshots.ps1`，选择根目录、输出位置和探查行数上限。初始化会打印逐层变化表，把建议深度和评估依据保存到私有配置。然后运行 `./drive-snapshot.ps1` 才生成文件大小快照。兼容命令 `./drive-snapshot.ps1 -Init` 会调用同一入口。

```powershell
# 无交互首次配置，各根目录分别应用默认增长策略。
./initialize-snapshots.ps1 -Path 'C:\','D:\' -OutDirRoot 'snapshots'
./drive-snapshot.ps1
```

初始化支持同样的策略、增长阈值和探查预算；显式 `-MaxDepth` 可为所选根目录统一指定深度，同时保留评估依据。扫描采用命令行 `-MaxDepth` → 匹配的 `maxDepthByPath` → 全局 `maxDepth`。旧版配置继续兼容；初始化不覆盖已有文件，需要修改时可编辑或使用另一个 `-Config`。

不完整评估会警告并保存暂定建议；根目录不可读时，需解决权限或显式指定深度才能保存。管理员初始化可在管理员 PowerShell 执行，或使用 `./drive-snapshot.ps1 -Init -Elevate`。Agent 使用 snapshot-capture skill 和同一入口，只补齐尚未明确的范围与偏好。`./tests/depth.ps1` 覆盖推荐、初始化和逐盘默认值。
