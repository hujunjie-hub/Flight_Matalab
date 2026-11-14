# Flight_Matalab 独立工程规格入口

## Agent 唯一操作入口

**将任务交给自动化 Agent 时，先要求它完整读取 [Agent 操作总指南](AGENT-操作指南.md)，然后按本页阅读顺序读取相关技术规格。** 所有正式技术、测试验收、问题管理和操作流程文档统一维护在 `spec/`。动态问题登记在 GitHub Issues，MATLAB 运行证据保存在 `work/validation/archives/`。GitHub 模板和可执行工具仍放在 GitHub/MATLAB 要求的固定路径，具体操作见 Agent 指南。

**本地执行统一原则：** 需要用户在本地操作时，优先提供“一个脚本、一条可复制命令、一个交付包”；双方职责和强制要求见[问题登记、状态流转与闭环规范第 7 节](quality/ISSUE_WORKFLOW.md#7-双方分工与固定工作循环)，MATLAB 具体入口见[本地 MATLAB 验证交接说明](validation/LOCAL_MATLAB_HANDOFF.md)。

基线：`FLIGHT-MATLAB-SPEC-1.3-DRAFT`；日期：2026-11-05；状态：`SPEC_REVIEWED_MODEL_NOT_STARTED`。

当前为规格阶段，工程已从Flight目录移出，与Flight和FMT-Model同级。独立工程根目录为 `D:/STM32Project/FMT-Firmware-1.2.0/Flight_Matalab`；原 `FMT-Model` 保留，用户已明确不回写原工程。三个目标 `.slx` 尚未生成，编译/仿真/代码生成结果均为 `NOT_RUN`。

本机UM982 GNSS与PPS是固定主要器件，目标QUAD_X4配置固定安装并启用；“信号中途丢失”是运行故障，不能改写成可选安装或无GNSS产品。GNSS PVT、PPS边沿和UTC历元分别建模、分别丢失/恢复；本地单调时钟与IMU不能因此停机。准确协议见[GNSS/PPS运行语义](FlightSIM-execution-protocol.md#8-固定gnsspps与运行中失锁)。最新核对UART4/RX DMA及PPS已强制启用，原生GNSS协议/UTC适配仍未完成，见[现状证据](validation/gnss_pps_configuration_observation.json)。最初观察到的固件关闭状态已在并行工作中被替换，只保留历史证据。

## 阅读顺序

1. [系统范围](FlightSIM-system.md)：三个模型各自解决什么问题。
2. [共享架构](FlightSIM-architecture.md)与[执行协议](FlightSIM-execution-protocol.md)：M1～M7、双clock、数值提交、准备/活动通道及参考grid。
3. [接口与单位](FlightSIM-interface-contract.md)、[数据回放](FlightSIM-data-replay.md)：模型连接前必须明确的契约。
4. [Stateflow](FlightSIM-stateflow.md)、[M5制导](FlightSIM-guidance.md)、[Simulink控制](FlightSIM-control.md)、[估计器](FlightSIM-estimator.md)：算法实现设计。
5. [Plant系统](QuadPlant-system.md)、[Plant架构](QuadPlant-architecture.md)：物理闭环和传感器模型。
6. [实施顺序](FlightSIM-implementation-plan.md)、[系统测试](FlightSIM-test-plan.md)、[Plant实施](QuadPlant-implementation-plan.md)、[Plant测试](QuadPlant-test-plan.md)。
7. [来源、决策与问题](FlightSIM-research-and-decisions.md)：保留依据、差异和进入改造前的门槛。

## 三个交付入口

| 新工程内目标 | 原工程参考 | 运行含义 |
|---|---|---|
| `simulation/FMT_DataSIM.slx` | [DataSIM.slx](../../FMT-Model/simulation/DataSIM.slx) | 原始测量回放，使用项目内部M3；开环算法重放 |
| `simulation/FMT_MILSIM.slx` | [MILSIM.slx](../../FMT-Model/simulation/MILSIM.slx) | 机体/传感器/执行器模型与控制系统构成真实软件闭环 |
| `simulation/FMT_ExtINS_DataSIM.slx` | [ExtINS_DataSIM.slx](../../FMT-Model/simulation/ExtINS_DataSIM.slx) | 外部导航结果回放；可由锁定KF-GINS MATLAB参考生成 |

三个入口通过相同公共核心工作，不能各维护一套FMS或控制器。只有MILSIM可报告闭环跟踪性能；另外两个入口的控制结果是反事实重算，不改变历史运动。

## 与固件规格的关系

[固件00](../../Flight/spec/00_工程基线与唯一权威规范.md)及[ICD02](../../Flight/spec/02_接口契约与公共数据规范.md)是上位输入，本次读入的02末尾CR-V191-M45-01及实际宏声明Schema6.0、QUAD Product/Port0x00010905（旧0x00010904摘要属历史）；准确文件Hash见validation/upstream_review_snapshot.json。本目录补充MATLAB模型组织、仿真调度、数据集与验证设计，不自行修改固件ABI、驱动或实机放行状态。

Stateflow负责状态/权限/故障/参考生命周期；Simulink负责离散数值数据流、控制器和Plant。MATLAB函数只承担导入、配置、离线参考及有限数值内核；不能用一个脚本包住整套FMS和Control后称为Simulink实现。

本规格的SIM_ONLY参数不代表用户实物参数。源码调研与API存在性检查不等于模型能编译；依赖核验和现有路径/配置警告见研究文档。全部未来目录、脚本、字典和模型在正文标为“规划”，不提供尚不存在脚本已运行的结论。

规格自检从独立工程根目录Flight_Matalab依次运行以下三个入口，分别重建反例证据、自测证据和总报告：

```powershell
python -B spec/tools/check_semantic_references.py
python -B spec/tools/test_check_specs.py
python -B spec/tools/check_specs.py
```

这些检查核对文档/锚点/需求映射、来源、设计算术及有限反例，不编辑/编译/仿真模型。独立fixture不等于自动证明任意修改后的正文；改变被检验数值/协议时须同步审查fixture与预期。输入Hash不一致会拒绝沿用旧PASS。已执行结果见[静态报告](validation/spec_review_report.json)、[设计算术](validation/design_arithmetic_report.json)与[源文件核对](validation/source_integrity_report.json)。上位交接/审核元数据的并行变化单独记录，不能把它误认为本会话改动。

本次新增R4～R6三轮13项，连同此前22项累计35项，详见[逐轮复审](FlightSIM-review-log.md)。除文档检查外，新增[可执行规格参考](validation/semantic_reference_report.json)，覆盖13项数学/协议反例及192组多项式导数界。

Host方案统一标HOST_NATIVE_V2：约束驱动retimer/GoalConnector、固定grid与未来交接、PREPARE/COMMIT、双时间轴和完整World证据。G0-HOST检查实际依赖/输入，G1验证模型拓扑；固件数值/时序等价另经FirmwareConformanceGate。模型实施仍未开始，任何规格PASS都不自动代替模型仿真。

独立目录关系和外部只读路径见[工程组织](FlightSIM-architecture.md#4-工程规划目录)。本次迁移保留所有历史证据的原始内容和原观察路径；它们不作为当前工作目录。当前迁移和逐文件核对见[迁移记录](validation/project_relocation_report.json)。


## 当前分支 MATLAB 实际验收

规格文档中的目标矩阵不自动代表代码已实现或已执行。当前分支的可执行测试入口、数据集版本、实际断言阈值、报告清单和结果提交格式，以 [MATLAB 仿真测试数据集与验收标准](MATLAB-验收与结果提交.md) 及 [机器可读验收清单](validation/matlab_acceptance_manifest.json) 为准。


## 问题登记与闭环

所有缺陷、测试失败和验收阻塞统一登记在 GitHub Issues；编号、状态、严重级别、证据 RUN_ID、修复 commit 和回归结果按 [问题闭环规范](quality/ISSUE_WORKFLOW.md) 管理。每次 MATLAB 运行的原始证据归档在被 Git 忽略的 `work/validation/archives/`，不与版本化的 `spec/validation/` 验收标准混放。


关闭问题前必须逐项执行[问题关闭验收清单](quality/ISSUE_CLOSURE_CHECKLIST.md)；机器可读状态定义见[issue-workflow.json](quality/issue-workflow.json)。
