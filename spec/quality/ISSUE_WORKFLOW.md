# 问题登记、证据归档与闭环规范

版本：1.0  
适用仓库：`hujunjie-hub/Flight_Matlab`  
适用分支：`main`（唯一工作分支）  
权威登记系统：GitHub Issues  
本地 MATLAB 交接：[LOCAL_MATLAB_HANDOFF.md](../validation/LOCAL_MATLAB_HANDOFF.md)

## 1. 唯一登记位置与编号

**所有缺陷、测试失败、规格缺口、集成问题和验收阻塞，统一登记在本仓库 GitHub Issues。**

- GitHub Issues 是唯一问题台账；不再额外维护 CSV、Excel 或第二份 Markdown 状态表，避免双重记录和状态不一致。
- 一个 Issue 对应一个可独立跟踪的根因/问题。一个测试运行发现多个独立问题时，分别建 Issue；同一根因造成多个现象时，可合并记录并列出全部表现。
- GitHub Issue 创建后，按编号生成项目问题 ID：`FMAT-0001` 对应 GitHub Issue `#1`，`FMAT-0027` 对应 `#27`。编号不复用。
- Issue 标题格式：`[FMAT-0001][S1][PLANT] 电机动态响应偏差`。创建前可暂用 `[MATLAB]`，创建后补齐正式 ID。
- Issue 正文中的 **Current status** 是当前状态；每次状态变化必须追加一条评论，记录日期、原状态、新状态、原因和证据。GitHub 原生 Open/Closed 只表示是否结案，不替代下面的细分状态。
- 当前已登记的主要问题为 FMAT-0012～FMAT-0017：#12 BLOCKED、#13 BLOCKED、#14 IN_PROGRESS、#15 FIXED_WAITING_RETEST、#16/#17 VERIFIED（GitHub Issue 仍保持 Open，待当前 main 回归后按关闭清单结案）。#2/#3/#4/#6/#10/#11 的正文曾记录 VERIFIED，但 GitHub Issue 仍 Open；#5 为 FIXED_WAITING_RETEST。每次处理前必须重新读取 Issue 正文和最新评论，不得仅凭本清单关闭问题。

## 2. 问题类型与严重级别

### 2.1 类型

| 类型 | 含义 |
|---|---|
| `BUG` | 代码/模型行为与明确规格不符 |
| `SAFETY` | 可能导致越权输出、碰撞、安全保护失效或错误放行 |
| `TEST_GAP` | 缺少必要测试、测试没有覆盖需求或断言不充分 |
| `SPEC_DEFECT` | 规格矛盾、接口/单位/边界定义错误或不完整 |
| `INTEGRATION` | 模块、固件、Host SIL、Simulink 或数据链路未正确接通 |
| `ENVIRONMENT` | MATLAB、编译器、依赖、路径或运行环境问题 |
| `PERFORMANCE` | 运行时间、求解率、数值稳定性或资源预算不满足要求 |
| `ENHANCEMENT` | 新需求或计划内能力扩展，不应伪装成缺陷 |

### 2.2 严重级别

| 级别 | 定义 | 验收处理 |
|---|---|---|
| `S0-CRITICAL` | 安全边界失效、未经授权的非零执行器输出、碰撞/围栏保护绕过、错误地将未验证结果放行为 PASS | 立即阻断相关验收/合并；先处理安全风险 |
| `S1-HIGH` | 核心飞行功能失效、关键数据错误、估计/控制显著偏差、核心接口不兼容 | 当前阶段不得验收通过 |
| `S2-MEDIUM` | 局部功能、诊断、非关键数值或测试质量问题 | 按阶段计划修复；影响验收的仍不得关闭 |
| `S3-LOW` | 文档、可读性、低风险维护性问题 | 可排期处理，必须明确是否影响当前交付 |

严重级别描述风险影响，不代表修复优先级可以脱离安全风险。S0/S1 不允许以“暂时不影响当前测试”为由静默豁免。

## 3. 问题状态与流转

Issue 正文必须有且仅有一个当前状态：

| 状态 | 含义 | 是否保持 GitHub Issue Open |
|---|---|---|
| `NEW` | 刚登记，尚未完成分类 | 是 |
| `TRIAGED` | 已确定类型、严重级别、所属模块和处理方式 | 是 |
| `NEEDS_INFO` | 缺少复现步骤、日志、数据或环境信息，等待补充 | 是 |
| `REPRODUCED` | 已按记录步骤稳定复现，或已由原始报告明确证实 | 是 |
| `IN_PROGRESS` | 正在分析根因、修改代码/模型/规格 | 是 |
| `FIXED_WAITING_RETEST` | 修复已提交，但尚未完成用户 MATLAB 回归验收 | 是 |
| `RETESTING` | 已收到修复后的新运行包，正在逐项复验 | 是 |
| `BLOCKED` | 被外部依赖、环境、上游接口或待确认决策阻塞 | 是 |
| `REOPENED` | 回归失败、问题复发或修复引入同类问题 | 是 |
| `VERIFIED` | 修复及回归证据已满足关闭条件，等待结案登记 | 是 |
| `CLOSED` | 已完成结案；必须记录结案类型和证据 | 否 |

标准主流程：

`NEW → TRIAGED → REPRODUCED → IN_PROGRESS → FIXED_WAITING_RETEST → RETESTING → VERIFIED → CLOSED`

允许的旁路：

- 信息不足：`NEW/TRIAGED → NEEDS_INFO → TRIAGED`。
- 外部阻塞：任何未结案状态可转 `BLOCKED`；阻塞解除后恢复到原工作状态，并在评论中说明。
- 回归失败：`RETESTING → REOPENED → IN_PROGRESS`，沿用原 Issue ID，不另建重复问题。
- 无法复现不等于自动关闭；先进入 `NEEDS_INFO`，记录已尝试的复现条件。确需结案时必须说明证据和原因。
- 重复问题可 `CLOSED`，但必须链接主 Issue；不计划修复必须记录技术理由并得到用户明确接受。

**特别约束：** 代码提交、PR 合并、静态检查通过或开发者本地单测通过，都不能把问题直接改成 `VERIFIED/CLOSED`。修复后必须有与修复 commit 对应的新 MATLAB 回归运行证据。

## 4. 每个问题必须登记的字段

GitHub Issue 使用仓库模板，至少记录：

1. Issue ID、标题、当前状态、类型、严重级别、模块。
2. 首次发现时间、发现分支和 commit SHA。
3. MATLAB Release、操作系统、编译器、Flight 上游 commit。
4. 发现问题的测试 ID、报告文件名、`RUN_ID`。
5. 前置条件、最小复现步骤、期望结果、实际结果。
6. 影响范围、安全影响、是否阻断当前阶段验收。
7. 原始证据文件名及 SHA-256；不确定根因必须明确写“待定位”，不能猜测为事实。
8. 修复 PR/commit、变更文件、根因说明。
9. 修复后的回归 `RUN_ID`、相关报告、实际结果和验收结论。
10. 结案类型、结案日期及验收依据。

问题记录中必须区分 **事实、推测、待验证假设**。没有证据的推测不得写成根因结论。

## 5. 文件与证据存放规则

| 位置 | 存放内容 | 是否提交 Git |
|---|---|---|
| `quality/ISSUE_WORKFLOW.md` | 本问题管理和闭环规范 | 是 |
| `.github/ISSUE_TEMPLATE/` | GitHub 问题登记模板 | 是 |
| `spec/validation/` | 版本化验收标准、数据契约、静态基线和机器可读 manifest | 是 |
| `work/validation/` | 当前一次 MATLAB 运行的临时报告和 Diary | 否，整个 `work/` 已在 `.gitignore` 中排除 |
| `work/validation/archives/<RUN_ID>/` | 单次运行不可覆盖的证据快照 | 否 |
| `work/validation/archives/<RUN_ID>.zip` | 对应运行证据包，便于提交验收 | 否 |
| GitHub Issue | 问题正文、状态历史、运行 ID、commit/PR 链接、证据附件/摘要 | 由 GitHub 保存 |

### 5.1 RUN_ID 规则

格式：`YYYYMMDDTHHMMSSfffZ_<project-commit-short>`。例如：

`20261109T193000000Z_247e534`

每次完整运行使用唯一 RUN_ID。运行包至少包含：

- 全部验收 JSON 报告；
- `component_checks.json`；
- `current_source_fingerprint.json`；
- `matlab_acceptance_diary.txt`；
- `scenarios/flight_sil_recording.mat` 的本次副本；
- `run_manifest.json`，记录 RUN_ID、MATLAB 环境、Flight/Flight_Matalab commit、工作区状态、总状态和各文件 SHA-256。

归档一经生成不得覆盖或修改。修复前后的运行必须使用不同 RUN_ID。

### 5.2 归档操作

在 MATLAB 运行完成后先关闭 Diary，再从仓库根目录执行：

```powershell
pwsh -File .\tools\archive_validation_run.ps1
```

脚本会将当前 `work/validation/` 的报告和日志复制到唯一归档目录，附上本次场景 MAT、生成文件哈希清单和运行元数据，生成 ZIP；归档成功后清空当前工作区的顶层临时报告，避免下一次运行混入旧报告。历史 `archives/` 不会被删除。

如果运行中断，也应保留失败报告和 Diary，并执行归档；运行状态会记录为失败/未完成，不得包装成 PASS。

### 5.3 证据提交

- 每次发现问题，Issue 必须引用发现它的 `RUN_ID` 和具体报告。
- 修复后，Issue 必须同时引用修复 commit/PR 和回归 `RUN_ID`。
- 优先将 ZIP 附加到对应 GitHub Issue；若文件过大或附件不可用，将 ZIP 发给验收方，并在 Issue 中记录文件名、ZIP SHA-256 和提交日期。
- 不把每次原始 MAT、日志和临时报告提交到 Git，避免仓库膨胀；需要作为阶段基线长期保存的摘要/manifest，另行经过评审后提交到 `spec/validation/`。
- 多个问题由同一运行发现时，可以共用同一个 RUN_ID/ZIP，不重复复制整套证据；各 Issue 指向相关报告和文件。

## 6. 问题关闭标准

只有同时满足以下条件才可进入 `VERIFIED` 并关闭：

- 根因已确认；或重复/不计划修复等结案原因已经明确记录并获接受。
- 修复代码/模型/规格已提交，Issue 关联精确 commit/PR。
- 相关针对性测试通过；涉及公共接口、调度、Plant、传感器、FMS、Control 或多入口行为时，必须运行完整 `run_component_checks`。
- 修复后的运行包与修复 commit、Flight 上游 commit、配置和数据指纹一致。
- 所有受影响报告均为预期结果；没有用 `PARTIAL/NOT_RUN/UNVERIFIED` 冒充 PASS。
- 原失败用例已回归通过，相关邻接用例未出现新回归。
- Issue 正文已补齐修复说明、回归 RUN_ID、证据哈希和验收结论。
- S0/S1 问题还必须确认安全影响已消除；不能仅凭一般 MIL 成功就认定实机安全放行。

若证据不足、报告不完整、Hash 不匹配或只完成代码修改，状态最多为 `FIXED_WAITING_RETEST`，不得关闭。

## 7. 双方分工与固定工作循环

当前仓库只保留并使用 `main`。历史开发分支和 PR #1 已不再是交付目标；PR #1 已合并到 main。所有修复、SPEC 更新和本地复测交接都直接围绕 main 的最新 HEAD 进行。

1. 用户运行 MATLAB，保存 Diary，生成并归档运行包，将 ZIP 发给验收方。
2. 验收方核对 commit、环境、Hash、报告、测试断言和已知缺口。
3. 对每个独立问题创建/更新一个 GitHub Issue，分配 FMAT ID，标记类型/严重级别/状态，并给出复现证据。
4. 验收方提出修复方案并在指定开发分支提交代码，Issue 记录 PR/commit，转为 `FIXED_WAITING_RETEST`。
5. 用户拉取修复 commit，重新运行完整验收，生成新的 RUN_ID 和证据包。
6. 验收方对照修复前后证据复验；通过后转 `VERIFIED` 并关闭，失败则原 Issue 转 `REOPENED`。
7. 每轮输出未关闭问题清单；未关闭问题不得从台账中删除。

## 8. 验收结果与问题状态是两套状态

- 测试结果：`PASS / FAIL / PARTIAL / NOT_RUN / UNVERIFIED`。
- 问题生命周期：本文件第 3 节定义的状态。
- 一个测试报告 `PASS` 不代表相关 Issue 自动关闭；一个 Issue `CLOSED` 也不代表整个阶段或项目 `PASS`。
- 当前阶段仍存在已知 P-10 Host MIL 端到端缺口；它必须作为明确的实现/集成问题或阶段遗留项跟踪，不能用总体 `PARTIAL_PASS` 抹掉其责任记录。


## 3.1 阻塞事件主动上报

阻塞事件与 Issue 生命周期状态相关但不完全等同。任何 P0/P1 验收门失败、关键测试意外未运行、构建/归档/Hash 失败、外部依赖不可用、证据冲突、用户数据覆盖风险或待确认架构/安全决策，都必须立即上报。

- 外部依赖、环境、缺失证据、上游接口或待用户决策导致无法继续时，Issue 使用 `BLOCKED`。
- 内部代码缺陷仍在修复时，Issue 保持 `IN_PROGRESS`，但 Agent 的每轮输出必须显式标记 `BLOCKER_IN_PROGRESS`。
- 只允许继续与阻塞项无依赖关系的独立工作；不得把受阻阶段标为完成。
- 阻塞解除后，Issue 恢复到阻塞前的工作状态，记录解除证据，并重新运行受影响测试。

每个阻塞事件必须记录：FMAT Issue、受阻阶段/验收门、分支/HEAD、命令与测试、期望/实际结果、证据 RUN_ID 和 SHA-256、事实/假设、影响及下游依赖、已尝试操作、推荐方案、是否需要用户决策、下一步与解除条件。没有证据必须标记 `EVIDENCE_MISSING`，不得猜测根因。

S0/S1 安全或执行器放行问题必须停止相关放行链路。禁止绕过测试、放宽阈值、降低样本分母、延长旧数据有效期、伪造 PASS 或覆盖用户工作区。发现同一 RUN_ID 的文档与原始报告不一致时，先登记证据冲突并冻结争议数字。

## 3.2 Agent 会话切换与交接

上下文空间不足或用户要求换会话时，旧 Agent 必须先保护工作区并更新版本化交接文档，记录最后已验证 commit、当前 PR HEAD、最后 RUN_ID/ZIP SHA-256、测试状态、未闭合 Issue、阻塞事件和下一步。新 Agent 必须重新读取 Spec、核对 Git/PR/Issue/归档证据并向用户确认接管状态；不能只凭旧会话摘要开始修改。未提交文件和用户本地模型/字典/录制数据不得被 reset、clean 或覆盖。
