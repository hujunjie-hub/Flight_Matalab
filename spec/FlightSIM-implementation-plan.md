# FlightSIM 实施计划

状态：NOT_STARTED；2026-11-05。本轮仅规格；以下目录、工具、模型、配置视图均是规划产物，尚未执行构建。

## 1. 依赖与前置

目标MATLAB/Simulink/Stateflow R2026b；安装可见不等于许可checkout或MEX通过。基础运行器使用SimulationInput和显式assertion，Simulink Test/Coverage可选；代码生成另需Coder门槛。OSQP使用锁定v1.0.0的mode2静态内核，实际MEX工具链须独立解已知QP。原FMT-Model仅只读选取资产，新工程不继承旧project启动脚本或generic全路径。

公用第三方按相对ProjectRoot的`../Flight/packages`或显式专用缓存解析，锁/Hash/许可证声明入新工程；不重复引入驱动或公用包。未来只在Flight_Matalab保存交付资产，不同步回原FMT-Model。工程根现为与Flight同级的独立Flight_Matalab；G0/G1的来源定位、字典、运行器和work目录均按架构第4节从ProjectRoot解析，不使用旧Flight/Flight_Matalab路径或依赖Flight工作目录。

## 2. 有向阶段依赖

| 阶段 | 完整交付 | 退出证据 | 状态 |
|---|---|---|---|
| G0-HOST 输入与接口基线 | 上位准确字段/版本快照、Host frame/rate决定、依赖/数据源锁、参数/端口schema及有界接口定义 | 输入可取得且Hash核对；语义和变更处置可复核，不要求尚未实现的G3 golden输出 | NOT_STARTED |
| G1 执行骨架 | 新.prj/显式path、共享字典接口、三入口引用唯一核心、function-call相位最小模型 | fixed-step discrete 500us、compiled执行序/无连续状态、单次事件次数与停机边界通过 | NOT_STARTED |
| G2 叶组件/输入 | 类型/配置生成器、Clock及固定GNSS的PVT/PPS/历元适配、几何/插值/队列、OSQP kernel、RK4 Plant叶组件、解析1kHz fixture | 独立已知向量/数据负向、P组件开环；两次生成Hash一致，GNSS/PPS安装/启用位均true | NOT_STARTED |
| G3 导航及外部参考 | Project22、Pristine21完整捕获Launcher、CONTROL_QUALIFIED适配 | 原生/扩展分开，init/CG/N0/延迟和full P证据；首批实际golden在此产生 | NOT_STARTED |
| G4 状态与制导 | 五域及PREPARE/COMMIT、固定grid、冷启动/恢复、V2 retimed M5/世界证据、Reference/Permit生命周期 | TransitionCatalog、任务/epoch/同刻事件与T-GDN通过 | NOT_STARTED |
| G5 控制与M7 | Read/Evaluate/Allocate/Commit、延迟MPC Job、SO3/PID/分配、量化code/应用延迟 | 真OSQP、fallback/AW/切换/帧code链通过 | NOT_STARTED |
| G6 两个回放 | DataSIM/ExtINS完整回放，依赖G2数据及G3～5核心 | 独立30s合格输入，错误数据拒绝；无物理闭环误报 | NOT_STARTED |
| G7 系统MIL | P开环合格的Plant、默认30s与静态对准35s、故障场景 | 时间/估计/控制/任务/着陆和覆盖率全部满足测试计划 | NOT_STARTED |
| G8 可交付回归 | 新进程冷启动矩阵、MIL记录再重放、来源/使用/报告与未通过项清单 | 实现后再做结构和边界两轮复审，无空壳或持续PD冒充MPC完成 | NOT_STARTED |

依赖为G0→G1→G2→G3→G4→G5→G6→G7→G8；Plant组件可随G2逐层实现，但最终闭环等G5/G6。G6首输入来自G2解析fixture，G7记录只作G8回归，避免循环。阶段没有自动派发Agent。

## 3. Host冻结与固件等价分开

G0-HOST冻结本规格选定的N0/rate、双时间轴、Read/Evaluate/Commit、PREPARE/COMMIT、grid和Host retimed planner；检查公共值类型、依赖、数据/配置和有界接口，模型保存HOST_NATIVE_V2标志。Host字典使用受控Auto值类型，不强制导入尚未选定的C生成Header。真正生成模型前仍须用户已明确的规格阶段完成后开始，并通过G1实际拓扑验证。

| Host前置 | 退出证据 |
|---|---|
| 执行协议 | 双clock/RunBinding、活动/准备槽、参考grid、数值提交、管理stop完整定义，无实现者猜值 |
| Profile与输入 | 四CORE+readonly Manifest、固定启用UM982/PPS及三路质量/失锁数据、P0/PSD/GM分开、地图调查/动态对象、coverage/结束语义、合格1kHz输入 |
| 依赖与库 | OSQP锁/模式/精度/稀疏结构/MEX编译器，KF21锁/数据，选定FMT_Model_Lib资产的策略及新配置集 |
| 可复核来源 | 采用02实际宏/M45-01的Schema6.0/Product-Port0x10905，含目标、质量/重力及自动垂向kind5；字段/Mask/维度快照准确，不把Host bus当C sizeof证据 |

FirmwareConformanceGate是后续声明固件可替换/等价前的独立门槛：固定N0/当前LLH-NED与rate对齐、Reference anchor与Control Time区分、双通道Port组合映射、retimed lattice/GoalConnector内部算法变更、World证据源接纳、管理stop策略、真实生产头/Host/ARM ABI和目标数值回归。它不以模糊待定字段阻挡已明确的Host方案，但未通过绝不标FIRMWARE_EQUIVALENT。Parent C01/C02关闭记录只按真实范围复用；后续C03的固件M6/OSQP链接批准不由本Host规格推定。

GNSS的目标不是待选择项：用户已确认UM982/PPS是主要固定器件，需支持信号中途丢失。最初只读核对曾发现固件关闭GNSS；末次核对已看到并行修改删除旧可选开关、在Kconfig/.config/rtconfig.h强制UART4/RX DMA并常驻PPS。sensor_alignment.native_backend仍为DISABLED，M2明确只有已解码PVT语义、无原生UART parser，协议/UTC适配与标定证据仍须完成。后续保持必需通道启用并验证原生后端/时间质量，不能用翻一个开关宣称导航已工作，也不能重建驱动框架。本次仍只改规格，差异与证据见研究第11节；Host合成路径可按固定目标实施，但不关闭这些固件门槛。

G0不要求先得到G3 golden输出；G1最小function-call/Model Reference骨架实际验证执行次序，失败回到整体方案修订。G6用G2解析fixture，G8才用G7记录回放，保持有向依赖。

## 4. 资产迁移原则

旧DataSIM保留回放思路，ExtINS保留外部导航定位，MIL保留物理闭环概念；入口和核心按本规格重建。MC-FMS拆M4/M5，CF-INS仅legacy诊断，MC-Controller旧归一化PID/混控不直接复用；MC-Plant只复用通过符号/数值验证的部分。每个选取源记录原文件/SID/Hash/许可证与新用途，不复制.git/旧路径或启动副作用。

## 5. 施工及完成证据

模型结构用model_edit分scope编辑，随后model_read/model_check；Stateflow先创建Chart再读取ID建内部结构，遇partial立即按实际状态处理。目录、模型文件名、Model Reference、字典和project注册分别验证；共享参数只用生成视图。

预先记录当前MATLAB项目/未保存模型；startup/shutdown幂等且恢复path，禁止clear all/restoredefaultpath覆盖用户会话。规划tools/run_flight_sim.m通过SimulationInput注入有限StopTime/typed Dataset并取SimulationOutput；外部参考在独立进程运行。

最终验收必须三入口真实compile+sim、完整运行矩阵、真QP与备用、错误路径、代码/数据/配置Hash和日志齐全。源378文件只读核对持续执行；阶段回退只处理新工程本阶段资产，不能回退并行固件或上位spec。当前编译/仿真/代码生成全部NOT_RUN。
