# Flight_Matalab 改造规格入口

基线：`FLIGHT-MATLAB-SPEC-1.1-DRAFT`；日期：2026-11-05；状态：`SPEC_REVIEWED_MODEL_NOT_STARTED`。

本轮只编写规格与只读调研证据。目标工程为 `D:/STM32Project/FMT-Firmware-1.2.0/Flight/Flight_Matalab`；原 `FMT-Model` 保留，用户已明确不回写原工程。三个目标 `.slx` 尚未生成，编译/仿真/代码生成结果均为 `NOT_RUN`。

## 阅读顺序

1. [系统范围](FlightSIM-system.md)：三个模型各自解决什么问题。
2. [共享架构](FlightSIM-architecture.md)：M1～M7及多速率调度。
3. [接口与单位](FlightSIM-interface-contract.md)、[数据回放](FlightSIM-data-replay.md)：模型连接前必须明确的契约。
4. [Stateflow](FlightSIM-stateflow.md)、[M5制导](FlightSIM-guidance.md)、[Simulink控制](FlightSIM-control.md)、[估计器](FlightSIM-estimator.md)：算法实现设计。
5. [Plant系统](QuadPlant-system.md)、[Plant架构](QuadPlant-architecture.md)：物理闭环和传感器模型。
6. [实施顺序](FlightSIM-implementation-plan.md)、[系统测试](FlightSIM-test-plan.md)、[Plant实施](QuadPlant-implementation-plan.md)、[Plant测试](QuadPlant-test-plan.md)。
7. [来源、决策与问题](FlightSIM-research-and-decisions.md)：保留依据、差异和进入改造前的门槛。

## 三个交付入口

| 新工程内目标 | 原工程参考 | 运行含义 |
|---|---|---|
| `simulation/FMT_DataSIM.slx` | [DataSIM.slx](../../../FMT-Model/simulation/DataSIM.slx) | 原始测量回放，使用项目内部M3；开环算法重放 |
| `simulation/FMT_MILSIM.slx` | [MILSIM.slx](../../../FMT-Model/simulation/MILSIM.slx) | 机体/传感器/执行器模型与控制系统构成真实软件闭环 |
| `simulation/FMT_ExtINS_DataSIM.slx` | [ExtINS_DataSIM.slx](../../../FMT-Model/simulation/ExtINS_DataSIM.slx) | 外部导航结果回放；可由锁定KF-GINS MATLAB参考生成 |

三个入口通过相同公共核心工作，不能各维护一套FMS或控制器。只有MILSIM可报告闭环跟踪性能；另外两个入口的控制结果是反事实重算，不改变历史运动。

## 与固件规格的关系

[固件00](../../spec/00_工程基线与唯一权威规范.md)及[ICD02](../../spec/02_接口契约与公共数据规范.md)是上位输入，本次读入的02声明Schema6.0、QUAD Product/Port0x00010904；准确文件Hash见validation/upstream_review_snapshot.json。本目录补充MATLAB模型组织、仿真调度、数据集与验证设计，不自行修改固件ABI、驱动或实机放行状态。

Stateflow负责状态/权限/故障/参考生命周期；Simulink负责连续数值数据流、控制器和Plant。MATLAB函数只承担导入、配置、离线参考及有限数值内核；不能用一个脚本包住整套FMS和Control后称为Simulink实现。

本规格的SIM_ONLY参数不代表用户实物参数。源码调研与API存在性检查不等于模型能编译；依赖核验和现有路径/配置警告见研究文档。全部未来目录、脚本、字典和模型在正文标为“规划”，不提供尚不存在脚本已运行的结论。

规格自检：从Flight目录运行`python Flight_Matalab/spec/tools/check_specs.py`，核对文档/锚点/需求映射、来源和独立设计算术并写validation报告；不编辑/编译/仿真模型。已执行结果见[静态报告](validation/spec_review_report.json)、[设计算术](validation/design_arithmetic_report.json)与[源文件核对](validation/source_integrity_report.json)。上位交接/审核元数据的并行变化单独记录，不能把它误认为本会话改动。

本次追加三轮复审从接口/职责、数值与因果执行、验收与交付三个视角替换22项问题，详见[复审记录](FlightSIM-review-log.md)。核心方案现为统一离散相位协调、显式RK4 Plant、MPC延迟Job、完整M5和量化输出链。

上位Mission字段/编译期围栏入口已随新版正文同步，尚需对齐Nav固定N0/rate语义并取得生产ABI/配置与依赖实证；详见[当前G0边界](FlightSIM-research-and-decisions.md#7-当前设计决定与g0退出)。这些前置条件没有被文档PASS自动关闭。
