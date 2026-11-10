# Agent 操作总指南（Flight_Matalab）

版本：1.0  
适用仓库：`hujunjie-hub/Flight_Matalab`  
当前开发分支：`optimize/sil-physical-parameter-alignment`  
唯一规范入口：`spec/README.md`

> **执行规则：Agent 每次接手任务，必须先读取本指南和引用的规范，再检查仓库现状。不得只依据对话摘要、旧报告或猜测修改代码、更新问题状态或宣布验收通过。**

## 1. Agent 必须读取的文件

按顺序读取：

1. 本文件 `spec/AGENT-操作指南.md`。
2. [Spec 总入口](README.md)：系统范围、文档地图和当前工程状态。
3. [MATLAB 测试数据集与验收标准](MATLAB-验收与结果提交.md)：验收入口、数据集、断言阈值、报告清单和已知缺口。
4. [系统级测试计划](FlightSIM-test-plan.md) 与 [Plant 测试计划](QuadPlant-test-plan.md)。
5. [问题登记、状态流转与闭环规范](quality/ISSUE_WORKFLOW.md)、[问题关闭清单](quality/ISSUE_CLOSURE_CHECKLIST.md) 和 [机器可读状态定义](quality/issue-workflow.json)。
6. [机器可读 MATLAB 验收清单](validation/matlab_acceptance_manifest.json)。
7. 根据任务读取相关架构、接口、状态机、Control、Guidance、Estimator、Plant、实施计划和决策文档。
8. 创建/更新 GitHub Issue 时，遵循仓库根目录的 `.github/ISSUE_TEMPLATE/matlab-acceptance-issue.md`。

**Agent 只扫描 `spec/` 时，也必须按本指南指引读取根目录下的 GitHub 模板和工具。它们是执行载体，不是另一套规范来源。**

## 2. 文档权威性和存放约定

- `spec/` 是所有正式技术规范、测试验收规范、问题管理规范和 Agent 操作规范的唯一版本化文档入口。
- `spec/README.md` 是文档地图；本文件是自动化 Agent 操作入口。
- `spec/quality/` 是问题管理规范的唯一正文位置。不得在其他目录另建第二份可独立修改的问题管理规范或 Markdown/CSV/Excel 问题台账。
- `spec/validation/` 保存版本化验收标准、测试数据契约、基线和机器可读 manifest。
- GitHub Issues 是问题动态状态的唯一台账；Git 中的规范只定义规则，不复制 Issue 的实时状态。
- `work/validation/archives/` 保存每次 MATLAB 运行的本地证据归档，不提交每次运行的原始大文件。
- `.github/ISSUE_TEMPLATE/` 是 GitHub 自动识别模板要求的固定位置；`tools/archive_validation_run.ps1` 是可执行归档工具。二者由本指南和 Spec 总入口引用，不属于规范正文。

规范冲突时先停止有争议的状态变更，报告冲突文件、段落和受影响需求；不得自行选择较宽松的阈值或安全约束。确认后同步更新正文、manifest、引用和相关测试。

## 3. 每次任务的仓库预检查

任何写操作前必须：

1. 确认仓库为 `hujunjie-hub/Flight_Matalab`。
2. 检查当前分支、HEAD commit、工作区状态、PR 状态和目标文件最新版本。
3. 默认只在用户指定的开发分支工作；当前约定分支为 `optimize/sil-physical-parameter-alignment`。
4. **不得直接写入 `main`、合并 PR、关闭 PR 或修改保护规则，除非用户明确授权。**
5. 查询现有 GitHub Issues，避免覆盖并发提交或创建重复问题。
6. 若 HEAD 已变化，基于最新 HEAD 重新读取文件和 tree；更新分支时使用 expected SHA 和非强制更新，不能覆盖并发提交。
7. 提交后重新读取分支和文件，核实 commit SHA、文件内容和 PR head；未核验成功不得声称提交成功。

## 4. MATLAB 验收执行流程

唯一自动化验收入口：

```matlab
run_component_checks
```

运行前提、依赖、测试顺序、数据集、断言阈值、必需报告和已知缺口以 [MATLAB 验收文档](MATLAB-验收与结果提交.md) 和 [机器可读验收清单](validation/matlab_acceptance_manifest.json) 为准。

执行时必须：

1. 记录 MATLAB Release、操作系统、编译器、Flight 上游 commit 和 Flight_Matalab commit。
2. 核对 Flight_Matalab 与 Flight 的目录关系、依赖锁和上游源 Hash。
3. 在完整 Diary 记录下运行完整验收入口；单项脚本不能冒充完整验收。
4. 检查必需 JSON 报告、子项状态、仿真终态及源/模型/配置/数据指纹。
5. 报告缺失、Hash 不匹配、运行中断、旧报告混入或证据不完整时，标记 FAIL 或 UNVERIFIED，不能给 PASS。
6. 按 MATLAB 验收文档关闭 Diary 后归档。

**能力边界：** 如果 Agent 当前环境不能访问用户 Windows 主机上的 MATLAB/Simulink、编译器或本地 Flight 工作树，只能进行静态审查和用户提交的证据复核。必须标注 `NOT_RUN` 或 `UNVERIFIED`，请用户运行并提供证据包；不得伪造 MATLAB 实测结果。

## 5. 运行证据归档

用户完成 MATLAB 运行并关闭 Diary 后，在仓库根目录执行：

```powershell
pwsh -File .\\tools\\archive_validation_run.ps1
```

归档工具：`tools/archive_validation_run.ps1`。归档位置：

```text
work/validation/archives/<RUN_ID>/
work/validation/archives/<RUN_ID>.zip
work/validation/archives/<RUN_ID>.zip.sha256
```

- 每次运行使用唯一 RUN_ID，禁止覆盖历史归档。
- ZIP 包含本轮报告、Diary、运行 manifest、输入 MAT 副本和各文件 SHA-256。
- ZIP 自身 SHA-256 通过同名 `.sha256` 文件核验。
- 归档脚本成功生成 ZIP 后会清理当前 `work/validation/` 顶层临时文件。**运行前必须确认 Diary 已关闭且本轮报告齐全。**
- 历史 `archives/` 不得清理或覆盖。
- 失败或中断运行也应保留现场并归档，状态记为 FAIL/INCOMPLETE。
- 原始归档不提交 Git；将 ZIP 附加到对应 Issue。若附件不可用或过大，由用户交给验收方，并在 Issue 记录 ZIP 文件名、SHA-256 和日期。

## 6. 问题发现、登记与编号

唯一问题登记位置是本仓库 GitHub Issues。不得使用 Markdown、CSV、Excel 或测试 JSON 另建动态问题台账。

发现问题后：

1. 先查询现有 Issues，判断是否已有相同根因或关联问题。
2. 一个独立根因一个 Issue；同一根因导致多个现象时合并记录。
3. 使用 `.github/ISSUE_TEMPLATE/matlab-acceptance-issue.md` 的字段结构。
4. 按 GitHub 实际分配的 Issue number 生成 `FMAT-{issue_number:04d}`。GitHub Issue 与 PR 共用编号序列，禁止假设下一个编号。
5. 记录 Type、Severity、Component、Current status、发现分支/commit、Flight 上游 commit、RUN_ID、测试 ID、报告文件、复现步骤、期望/实际结果、影响和证据 SHA-256。
6. 根因未知时写“待定位”；事实、假设和待验证项必须分开。
7. 每次状态变化更新 Issue 正文中的 Current status，并追加评论记录日期、原状态、新状态、原因、操作者和证据。
8. 预期 PARTIAL 不应伪装成 BUG；已确认的计划缺口可按 INTEGRATION/ENHANCEMENT 登记，并标明是否阻断当前阶段。

类型、严重级别和状态定义只使用 [问题闭环规范](quality/ISSUE_WORKFLOW.md)，不得自行增加同义状态。

## 7. 修复与回归闭环

标准流程：

`NEW → TRIAGED → REPRODUCED → IN_PROGRESS → FIXED_WAITING_RETEST → RETESTING → VERIFIED → CLOSED`

允许 `NEEDS_INFO`、`BLOCKED` 和 `REOPENED` 分支，详见问题闭环规范。

1. 修复前确认根因和复现条件，不能只针对表面日志打补丁。
2. 修改代码、模型、配置、规格或测试时，检查是否需同步接口契约、数据集、阈值依据、manifest 和指纹逻辑。
3. 每个修复 commit/PR 关联 Issue ID，记录根因、变更文件和风险。
4. 修复提交后最多进入 `FIXED_WAITING_RETEST`，等待用户在目标 MATLAB 环境运行新一轮完整测试。
5. 回归使用新的 RUN_ID；核对修复 commit、Flight 上游 commit、配置/模型/数据指纹。
6. 原失败用例和受影响邻接用例通过后才可进入 `VERIFIED`，再按关闭清单转 `CLOSED`。
7. 回归失败沿用原 Issue 转 `REOPENED`，不得另建重复 Issue。
8. 没有用户 MATLAB 实测证据时，不得把修复提升为 VERIFIED/CLOSED。

## 8. 四套状态必须分开

- 测试状态：`PASS`、`FAIL`、`PARTIAL`、`NOT_RUN`、`UNVERIFIED`。
- 问题状态：问题闭环规范定义的 11 种生命周期状态。
- PR 状态：Open/Draft/Merged 等 GitHub 状态。
- 阶段状态：由阶段验收矩阵决定。

Issue CLOSED 不等于阶段 PASS；报告 PASS 不自动关闭 Issue。当前已知 P-10 Host MIL PPS/RECTIME 端到端缺口必须如实保留，不能把 PARTIAL_PASS 改写为 PASS。

## 9. Agent 每轮必须输出

1. 仓库、分支、HEAD commit 和 PR 状态。
2. 实际读取和修改的文件。
3. 实际执行的命令/测试；未执行项目明确写 NOT_RUN。
4. 新建/更新 Issue 的 FMAT ID、标题、类型、级别、状态和链接。
5. 修复 commit/PR，以及与 Issue 的关联。
6. 测试状态、证据 RUN_ID；没有证据则写 UNVERIFIED。
7. 未关闭问题、阻塞项、已知缺口和下一步。
8. 是否修改 main；默认不得修改。

## 10. 禁止事项

- 不得把静态审查、代码生成、模型存在或单项测试描述为 MATLAB 实测通过。
- 不得伪造 RUN_ID、报告、SHA-256、Issue 编号、复现结果或测试结论。
- 不得为制造 PASS 擅自放宽阈值、改变 seed、删除失败用例或缩短测试窗口。
- 不得删除/覆盖历史证据归档。
- 不得在缺少用户回归证据时关闭问题。
- 不得绕过 FMS 授权、安全门、导航有效性或候选轨迹独立验证约束。
- 不得未经用户明确授权合并 main、关闭 Draft PR 或宣称实机/飞行放行。


## 11. 阻塞项主动上报（强制）

Agent 不得静默跳过阻塞，也不得为了继续推进而自行改变架构、安全条件、验收阈值或测试分母。以下任一情况必须立即作为阻塞事件上报：

- P0/P1 验收门失败、关键测试意外 NOT_RUN/UNVERIFIED，或无法达到既定验收阈值；
- 构建、测试、归档、哈希校验或必要工具执行失败；
- 当前任务依赖的上游接口、分支、提交或外部环境不可用；
- 规格、代码、Manifest、Issue 或同一 RUN_ID 证据之间存在冲突；
- 工作区存在无法安全归类的用户修改，继续操作可能覆盖数据；
- 需要用户决定架构、安全策略、硬件行为或验收标准。

### 11.1 上报时限与状态

1. 发现后立即报告，不得等到整轮任务结束；先停止受影响的依赖工作。
2. 若确实被外部依赖、环境、缺失证据、上游接口或待确认决策阻断，关联 Issue 状态转为 `BLOCKED`，并记录阻塞原因；内部代码缺陷仍在处理中时保留 `IN_PROGRESS`，但报告中必须标记 `BLOCKER`。
3. 不受该阻塞影响的独立任务可以继续，但必须说明隔离边界；不得把依赖阻塞项的阶段标为完成。
4. 解除阻塞后，记录解除证据和恢复状态，并重新运行所有受影响测试。

### 11.2 每个阻塞事件必须报告

- Blocker ID / 对应 FMAT Issue；
- 阻塞的阶段、验收门和具体任务；
- 发生时间、分支、HEAD、命令/测试名称；
- 期望结果与实际结果，精确错误/状态/数值；
- 证据文件、RUN_ID、SHA-256 或日志位置；
- 已确认事实、待验证假设必须分开；
- 影响范围、被阻断的下游任务及可独立继续的任务；
- 已尝试的处理及结果；
- 可选解决路径、风险和 Agent 推荐方案；
- 是否需要用户决策；若需要，只提出一个清晰、具体的决策请求；
- 下一步动作、负责人和解除条件。

不得只写“有问题”“测试失败”或“无法继续”。没有证据时明确写 `EVIDENCE_MISSING`，不得编造日志或根因。

### 11.3 安全与验收停机规则

- S0/S1 安全问题、Permit/FMS/执行器越权风险、证据完整性问题：立即停止相关放行链路，不得绕过继续验收。
- 不得放宽阈值、跳过断言、减少样本、延长过期数据、伪造状态或把 NOT_RUN 改成 PASS。
- 不得为了消除 BLOCKED 而擅自修改上位 Flight 固件接口或安全策略；需按对应仓库分支/PR/Issue 独立处理。
- 如发现同 RUN_ID 文档与 JSON 不一致，以原始归档证据为准并登记冲突；在核清前不得传播有争议数字。

## 12. Agent 会话切换与新会话接管（强制）

当上下文空间不足、任务跨度过大或用户要求更换会话时，必须开启新 Agent 会话。不得通过继续压缩旧会话上下文来冒险执行关键修改。

### 12.1 旧会话结束前

1. 停止开始新的大范围修改；先检查 `git status --short`、HEAD、分支、staged/unstaged diff 和未跟踪文件。
2. 保护所有未提交用户修改；对文本 diff 和未跟踪模型/字典/录制文件分别备份，不得 reset/clean/checkout 覆盖。
3. 更新 `spec/validation/next-phase-delivery.md`：记录最后一个已验证 commit、最后一个真实 RUN_ID、ZIP SHA-256、实际 PASS/FAIL/PARTIAL/NOT_RUN、未闭合 Issue、阻塞项和下一步。
4. 对每个阻塞事件更新 GitHub Issue；不要只把阻塞写在聊天总结中。
5. 明确区分“最后验收归档的 commit”和“当前 PR HEAD”；不得声称归档验证了更晚的代码。
6. 输出一份可直接复制到新会话的交接任务，包含新会话必须先读取的文件和核对命令。

### 12.2 新会话启动

新 Agent 必须从零接管，第一轮先执行：

1. 读取本指南、`spec/README.md`、`spec/validation/next-phase-delivery.md`、验收文档、Manifest、Issue 工作流和所有相关未关闭 Issue。
2. 核对 GitHub 分支、HEAD、PR head、Flight 上游 commit 和当前工作区状态。
3. 核对最后一次 RUN_ID、ZIP SHA-256 和报告中的实际状态。
4. 对照旧会话交接内容逐项确认；若文档、GitHub 和 ZIP 有冲突，先报告 BLOCKER，不得猜测。
5. 向用户输出“接管确认”：当前分支/HEAD、最近验证基线、未提交修改、未关闭 Issue、P0/P1 阻塞和第一项执行任务。
6. 只有核对完成后才能开始写代码。

新会话不得仅凭旧会话摘要继续，也不得重复已经由同一 commit + RUN_ID 证明通过的工作；但涉及当前 HEAD 变化、证据冲突或回归风险时，必须重新验证。

## 13. 每轮输出增加阻塞摘要

在第 9 节固定输出之外，Agent 每轮必须在开头增加：

- `BLOCKER_STATUS: NONE | BLOCKED | BLOCKER_IN_PROGRESS`；
- 阻塞数量及对应 FMAT Issue；
- 本轮是否有任务被阻断；
- 是否需要用户决策；
- 不受阻塞影响、可以安全继续的工作；
- 阻塞解除的明确条件。

若没有阻塞，必须明确写 `BLOCKER_STATUS: NONE`，不能省略该字段。
