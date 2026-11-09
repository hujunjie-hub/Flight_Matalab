# MATLAB 仿真测试数据集与验收标准

版本：1.0
适用分支：`optimize/sil-physical-parameter-alignment`
适用仓库：`hujunjie-hub/Flight_Matalab`
状态：本文件定义当前分支可执行验收流程；实际结果以本次 MATLAB 生成的报告和源数据指纹为准。

> **验收原则**：代码存在不等于测试通过；静态审查通过不等于 MATLAB 编译通过；单项核心算法通过不等于 MIL 端到端通过。所有 PASS 必须来自当前代码、模型、配置和数据的实际运行报告。

## 1. 唯一验收入口

当前分支统一使用以下命令完成构建、组件测试、Plant 测试、传感器事件测试、Flight 三入口回放和数据指纹记录：

```matlab
run_component_checks
```

该入口执行顺序：

1. 重建同级 `Flight` 仓库的 Windows Host SIL 运行库。
2. 重建本项目原生 MEX、生成参数字典和 Plant/Flight/Actuation 模型。
3. 执行 `verify_flight_entries(true)`：运行 26 s 默认 MIL 闭环，刷新 `scenarios/flight_sil_recording.mat`，再执行 DataSIM 和 ExtINS DataSIM 回放。
4. 运行参数视图、OSQP、G1 执行拓扑、Plant 开环、传感器事件时序、TimeService、GNSS 失锁恢复、RECTIMEA、truth 隔离、PID 和执行器测试。
5. 对代码、测试、配置、顶层 `.slx` 模型、回放数据和 MEX 产物计算 SHA-256 指纹，并检查测试过程中输入未发生变化。

如 MinGW 不在默认目录，可传入编译器目录：

```matlab
run_component_checks('C:\STM32CubeCLT\mingw64\bin')
```

默认编译器目录为 `D:\STM32CubeCLT\mingw64\bin`。运行前需打开 `Flight_Matalab.prj`，确认 `mex -setup C` 已选择可用 C 编译器，并确保 Windows `pwsh` 可执行。

## 2. 工程和依赖前提

- `Flight_Matalab` 与 `Flight` 必须处于同级目录；本项目从 `../Flight` 读取固件权威参数、Host SIL 源码、TimeService、GNSS 和 UM982 协议实现。
- `config/firmware_sources.json`、`config/flight_baseline.json`、`external_dependencies.lock.json` 是依赖与版本核验依据。不要用不匹配的 Flight 工作树运行后再把结果作为本分支验收。
- 默认构建脚本使用 Windows PowerShell 7（`pwsh`）和 MinGW GCC/G++。编译器缺失、依赖路径错误、上游源文件 Hash 不匹配都属于构建失败，不是可忽略警告。
- 每次拉取新代码、修改配置、模型或测试数据后，都必须重新运行完整入口；不得沿用旧的 `work/validation` 报告、旧 DLL/MEX 或旧模型缓存。
- `config/SIM_ONLY/QUAD_X4` 是仿真专用参数，不是实机标定数据；当前通过只代表当前 SIM_ONLY 配置下的数值/软件行为符合相应标准。

## 3. 测试数据集清单

### 3.1 默认 MIL 命令序列

| 项目 | 定义 |
|---|---|
| 生成位置 | `tools/fmt_default_input.m` |
| 入口 | `FMT_MILSIM` |
| 时间网格 | 0～26 s，500 μs 固定步长 |
| 命令 | 1=解锁，3=起飞至 2 m，4=降落，2=上锁 |
| 命令行索引 | MATLAB 1-based 行索引 `[8000, 8200, 24000, 48000]` |
| 预期任务 | 完成解锁、起飞、降落和上锁；不得在无有效提交许可时输出非零推力 |

命令脉冲由代码生成，不依赖手工编辑的外部 CSV。验收时以当前分支 `fmt_default_input.m` 为准。

### 3.2 Flight 回放数据集

| 项目 | 定义 |
|---|---|
| 文件 | `scenarios/flight_sil_recording.mat` |
| 基线 Git blob | `f3106ca4d4394f3761ef813879bd603fb85a3bb4` |
| 基线大小 | 7,606,547 bytes |
| 数据变量 | `t`、`sensor`、`commands`、`navigation`、`revision` |
| 生成方式 | `verify_flight_entries(true)` 从本次 MIL 闭环输出生成 |
| 使用位置 | `FMT_DataSIM` 与 `FMT_ExtINS_DataSIM` |

完整验收入口会自动重新生成该 MAT 文件，再使用新录制数据执行两种回放。上表 Git blob 仅用于识别当前分支初始数据版本；重新生成后文件内容可以变化。重新生成后的权威 SHA-256 记录在 `work/validation/current_source_fingerprint.json` 的 `files` 字段中，不能继续拿旧 Git blob 值判定新数据是否一致。

### 3.3 Plant 解析与数值测试数据

Plant 测试向量由 `tests/verify_plant_open_loop.m` 确定性生成，使用当前 `config/SIM_ONLY/QUAD_X4` 配置和从同级 `Flight/config/vehicle_model.yaml` 读取的权威质量、惯量、电机几何、推力限制及电机时间常数。主要 fixture 如下：

| 测试 | 输入数据/工况 |
|---|---|
| P-01 | 四电机 0→5 N 阶跃，运行 1 s |
| P-02/P-03 | 四路等推力及单路电机 wrench 几何符号 |
| P-04 | 关闭阻力和接触的 0.1 s 自由落体 |
| P-05 | 以 mg/4 平衡重力，运行 2 s |
| P-06 | 非零 yaw/rate 初值，分别使用 q 和 -q |
| P-07 | 2 rad/s 机体旋转、非零 IMU/GNSS 杆臂；另用 2 ms IMU 周期和非恒定线/角加速度、jerk 检查差分时间窗 |
| P-08 | 静止水平 IMU 与 1 m/s NED 速度，验证固定 N0 Earth-rate/Coriolis |
| P-09 | 10 s、500 μs Plant 步长、固定 seed 20261109；同 seed 重复、不同 seed、噪声 STD/轴间相关性、bias/scale 注入 |
| P-11 | 初始离地 0.1 m 的落体接触测试，运行 2 s |
| P-12 | 5 s 悬停/偏航，500 μs Simulink RK4 对比独立 250 μs RK4 |
| P-13 | 单电机 50% effectiveness 和 1.25 N 外部 NED 力 |
| P-15/P-16/P-17 | 离地 1 cm 无接触力、静态 mg/k 接触平衡、水平滑动且无地面摩擦 |
| P-18/P-19/P-20 | FRD/NED 力转换、风相对阻力、非对角正定惯量耦合 |
| P-21 | NaN、非法环境开关、超界 effectiveness、非对称/非正定惯量拒绝 |

P-14 不在上述 Plant 开环脚本中执行，由 `tests/verify_truth_isolation.m` 单独验证 Plant truth 不得绕过传感器合成进入 Flight 导航/控制。

### 3.4 传感器多速率事件数据

`tests/verify_sensor_event_timing.m` 生成 500 μs 固定步、1,000,000 μs 起始 epoch、1.2 s 测试窗口，构造 IMU/GNSS/MAG/Baro 四通道事件。测试覆盖 sample/capture/arrival/release 时间顺序、各自采样周期、队列迟到、计数守恒、每通道抑制一个样本后的 sequence gap、消费者速率、延迟边界、过期拒绝、非单调时间和非法 validity mask。

Host SIL 的确定性调度器必须显式模拟 RTOS 信号量唤醒：Sensor 任务产生有效 GNSS origin candidate 后，Mission 必须在候选头有效期内立即执行 FMS origin-reset 授权；Mission 写入 `EstimatorResetRequest` 后，Sensor 必须立即消费该请求。不能只依赖 20 ms Mission 周期轮询，因为当前 SIM_ONLY GNSS 为 100 ms 采样、10 ms 传输、20 ms measurement TTL，固定周期调度会在某些相位下错过候选有效期。MIL gate 必须证明 `NAV_VALID_HORIZONTAL_POSITION` 和 `PREARM_READY` 实际出现；不得通过延长 TTL、跳过 FMS 授权或伪造导航有效位规避。

### 3.5 Flight 时间与 GNSS 测试数据

- `verify_time_service_sync`：编译同级 Flight 的真实 `systime.c`，调用上游 `tests/time/test_time_service.c`；PPS 输入是确定性合成 `PpsCaptureEvent`。
- `verify_gnss_time_recovery`：编译真实 TimeService、GNSS sample normalization/filter/calibration 源码，调用上游 `tests/drivers/test_gnss_outage.c`；覆盖 PVT、PPS、UTC 独立失效、holdover 和重捕获。
- `verify_rectime_time_mapping`：编译真实 `unicore_ascii.c` 与 `systime.c`，构造有效/损坏 RECTIMEA 字节帧，检查 CRC、GPS week/TOW、UTC 日历交叉检查和 PPS 配对。

这些测试使用合成 capture/tick/字节夹具验证真实固件算法核心，不代表真实 TIM2 capture ISR、UART/DMA 或 Host MIL 的 `sensor_gnss_poll` 端到端链路已经实现。

### 3.6 仿真参数数据

当前仿真参数来源：

- `config/SIM_ONLY/QUAD_X4/vehicle_model.yaml`
- `config/SIM_ONLY/QUAD_X4/sensor_alignment.yaml`
- `config/SIM_ONLY/QUAD_X4/profile_manifest.json`
- `config/SIM_ONLY/QUAD_X4/estimator_tuning.yaml`
- `config/SIM_ONLY/QUAD_X4/controller_tuning.yaml`
- 同级 `Flight/config/vehicle_model.yaml` 和 `config/firmware_sources.json` 指定的固件输入。

修改以上任一输入后必须重跑验收。配置中的噪声、安装矩阵、杆臂、气动、地面接触和电机推力系数均属于 SIM_ONLY 假设，不能作为实物标定结论。

## 4. 当前自动化验收矩阵

| 验收范围 | 执行入口/报告 | 当前分支接纳要求 |
|---|---|---|
| 构建和依赖 | `component_checks.json` | 所有构建步骤完成；异常必须 FAIL，不能继续使用旧产物 |
| Flight 三入口及回放 | `flight_entries.json`、`mil_diagnostics.json`，并嵌入 `component_checks.json` | 报告 PASS；26 s MIL 完成任务，DataSIM/ExtINS 对比一致，缺测禁止推力；MIL 失败时必须保留逐命令 ACK 与 PreArm 诊断 |
| 参数一致性 | `parameter_view_report.json` | PASS；26 项 Plant、19 项 Sensor、54 项 SensorModel、10 项 SensorTiming 参数合同正确 |
| Plant 开环 | `plant_open_loop_report.json` | `implemented_gate_status=PASS`，但整体 `status=PARTIAL` 是当前预期 |
| 传感器事件队列 | `sensor_event_timing_report.json` | PASS；计数守恒、sequence gap 和时间因果关系正确 |
| TimeService 核心 | `time_service_sync_report.json` | PASS；但不能据此认定 Host MIL PPS 已端到端接通 |
| GNSS 失锁恢复核心 | `gnss_time_recovery_report.json` | PASS；PVT/PPS/UTC 独立失效和恢复用例通过 |
| RECTIMEA 核心 | `rectime_time_mapping_report.json` | PASS；真实解析器核心通过，物理 UART/PPS 接口仍不在范围内 |
| OSQP MEX | `osqp_mex_report.json` | PASS；只代表独立已知最优值/KKT/MEX 检查，不代表 MPC 闭环求解门限已通过 |
| G1 执行拓扑 | `g1_execution_report.json` | PASS；只代表 G1 调度/拓扑测试，不代表完整 Flight 算法验证 |
| PID 状态事务 | `rate_pid_report.json` | 已执行项目 PASS；报告中 `NOT_RUN` 字段必须保留，不得升级为完整 M6 闭环 PASS |
| PID 分配反馈 | `pid_allocator_feedback_report.json` | PASS；同 tick 分配反馈和失败不提交状态 |
| 执行器数值组件 | `actuation_report.json` | 已执行数值项目 PASS；Permit 生命周期、500 μs frame apply、ground stop transaction 仍为 NOT_RUN |
| 真值隔离 | `truth_isolation_report.json` | PASS；Plant truth 只能到传感器合成和只读评估出口 |
| 输入与模型数据指纹 | `current_source_fingerprint.json` | 必须存在；必须包含 `simulation/`、`scenarios/`、`.mat` 数据集及本分支测试/配置的 SHA-256 |

所有必需报告必须来自同一次验收运行。报告缺失、时间戳/Hash 不一致、输入在测试期间改变或运行中断，都不能按 PASS 验收。

Flight 入口诊断约定：`verify_flight_entries` 在 MIL 断言之前写出 `mil_diagnostics.json`，记录每条命令的 command code、request ID、ACK state/reason，以及对应时刻的 arm/mode/failsafe、PreArm state、failed mask、primary reason、failed count、check epoch 和 authority。Host SIL 状态帧宽度为 32；第 25～32 列依次为 PreArm failed mask、primary reason、failed count、warning count、check epoch、FMS authority、mission state、最近命令码。不得使用最后一条 DISARM ACK 代替 ARM ACK 诊断。

## 5. Plant 数值验收阈值

| ID | 当前脚本判据 |
|---|---|
| P-01 | 电机转速响应单调；5 tau 时相对目标误差 <1% |
| P-02 | 四路等推力 wrench 与 `[0,0,-4,0,0,0]` 的无穷范数误差 <1e-10 |
| P-03 | 单电机 wrench 与 Flight 几何推导矩阵误差 <1e-10 |
| P-04 | 0.1 s 自由落体位置和速度解析误差分别 <1e-6 m、<1e-6 m/s |
| P-05 | 2 s 悬停速度漂移 <1e-6 m/s |
| P-06 | q/-q 物理轨迹一致性 <1e-12；四元数范数误差 <1e-6 |
| P-07 | 杆臂运动学解析误差 <1e-6；2 ms IMU 采样 epoch 才允许更新 IMU validity 和差分历史 |
| P-08 | 静止比力误差 <1e-10；Earth-rate 误差 <1e-12；Coriolis/比力误差 <1e-10 |
| P-09 | 同 seed 序列完全一致、不同 seed 序列不同；10 s 噪声 STD 落入 95% 卡方区间；gyro 轴间相关性 <0.05；bias/scale 注入误差 <1e-9 |
| P-10a | sample ≤ capture ≤ arrival ≤ release；opportunities=generated+suppressed；generated=released+pending；released=accepted；抑制后 sequence gap 可见 |
| P-10b | TimeService、GNSS outage、RECTIMEA 核心各自独立 gate 通过；但 Host MIL 端到端 PPS/RECTIME 未实现，P-10 总体 PARTIAL |
| P-11 | 全程有限、法向力非负，基准场景最大穿透 <0.02 m |
| P-12 | 500 μs 与独立 250 μs RK4 对比：最大位置差 <1e-3 m、姿态差 <1e-4 rad |
| P-13 | 电机 effectiveness 和外部 NED 力进入 Plant 动力学，解析误差按脚本断言 |
| P-14 | 独立 truth-isolation 图依赖检查 PASS |
| P-15 | 离地 1 cm 时法向接触力严格为 0 |
| P-16 | 静态压缩法向力与 mg 误差 <1e-8 N，接触力矩无穷范数 <1e-8 |
| P-17 | 第一版无水平摩擦，滑动时接触 wrench 与纯法向力误差 <1e-8 |
| P-18 | FRD/NED 力转换与完整惯量力矩解析误差 <1e-10 |
| P-19 | 风阻按 `v_NED - wind_NED` 计算，解析误差 <1e-10 |
| P-20 | 非对角惯量、陀螺耦合和角加速度解析误差 <1e-9 |
| P-21 | NaN/非法开关/超界 effectiveness/非对称或非正定惯量必须拒绝 |

以上是当前测试代码中的断言阈值，不得在测试失败后通过放宽阈值、改变 seed 或缩短评价窗口来制造 PASS。若物理模型发生有依据的变化，必须先更新需求、测试向量、阈值依据和版本记录，再执行新一轮验收。

## 6. 总体验收状态定义

| 状态 | 判定规则 |
|---|---|
| `FAIL` | 构建失败、任一已实现测试断言失败、仿真提前结束、报告缺失、数据/模型 Hash 不一致或运行输入不完整 |
| `PARTIAL_PASS` | 当前已实现的组件 gate 全部通过，Flight 三入口回放通过，且明确保留未实现的 P-10 Host MIL PPS/RECTIME 集成等缺口 |
| `PASS` | 当前阶段所有要求均已实现并通过；当前分支由于 P-10 Host MIL 端到端链未完成，不允许给出整体 PASS |
| `NOT_RUN` | 没有当前运行证据，或只有静态审查/旧报告 |

本分支正常预期是 `component_checks.json.status=PARTIAL_PASS`、`plant_open_loop_report.json.status=PARTIAL`、`flight_entries.json.status=PASS`。这不是矛盾：前两者如实保留尚未实现的边界，最后一项表示当前三入口基础 MIL 回放通过。

## 7. 当前已知缺口（不得误报通过）

1. P-10 Host MIL 端到端 TIM2 capture、UM982 UART/DMA、`sensor_gnss_poll` 和 UTC 映射链尚未接入；`pps_backend` 当前为 `DISABLED_LOCAL_MONOTONIC`。
2. OSQP 当前验证的是独立 MEX 已知最优值和 KKT，不等于 MPC 模型中的 QP 组装、严格候选门限和实际控制周期全部验证。
3. G1 gate 验证执行拓扑和节拍，不等于三入口完整 FMS/Guidance/Control 的所有系统状态覆盖。
4. PID 与执行器报告中的 `NOT_RUN` 项仍是未验收项目，不能只看报告顶层 PASS。
5. Flight 三入口当前集成验收为 26 s 默认任务，不等于旧版系统规格中所有 30 s、故障矩阵、MPC RMS 和覆盖率要求均已实现。
6. 当前所有结果仅是 PC MATLAB/Simulink + Windows Host SIL/SIM_ONLY 模型验证，不构成 MCU 实时性、PIL/HIL、传感器实物标定或实飞放行。

每次运行后，先关闭 Diary，再归档；不要直接覆盖上一轮证据。

```matlab
root=flight_startup;
reportDir=fullfile(root,'work','validation');
if ~isfolder(reportDir), mkdir(reportDir); end
diary(fullfile(reportDir,'matlab_acceptance_diary.txt'));
diary on;
run_component_checks;
diary off;
```

然后在仓库根目录执行：

```powershell
pwsh -File .\\tools\\archive_validation_run.ps1
```

归档脚本会生成唯一 `RUN_ID`，把本轮所有 JSON 报告、Diary、源数据指纹和本次 `flight_sil_recording.mat` 副本放入 `work/validation/archives/<RUN_ID>/`，生成 `<RUN_ID>.zip`，并记录 Flight_Matalab/Flight commit、运行状态及各证据文件的 SHA-256；ZIP 自身的 SHA-256 写入同名 `.sha256` 校验文件。归档成功后只清空当前工作区顶层临时文件，历史 `archives/` 不会被删除。每个 RUN_ID 不可覆盖；失败或中断的运行也要归档，状态保留为 FAIL/INCOMPLETE。

`work/` 已由 `.gitignore` 排除，因此原始 MAT、日志和每轮报告不直接提交到 Git。把 ZIP 附加到对应 GitHub Issue；若附件不可用或过大，就把 ZIP 发给验收方，并在 Issue 中登记文件名、SHA-256 和提交日期。不要只发截图或最后一行报错。

问题登记、状态流转、证据目录和关闭标准见 [问题闭环规范](quality/ISSUE_WORKFLOW.md)。每个 Issue 必须引用发现它的 RUN_ID；修复后还必须引用修复 commit 和新的回归 RUN_ID。

## 9. 我方验收输出

收到运行包后，除测试验收外，还会按 [问题闭环规范](quality/ISSUE_WORKFLOW.md) 对每个独立问题建立/更新 GitHub Issue，分配 `FMAT-xxxx` 编号，记录严重级别、当前状态、复现步骤和证据。问题未经过修复后回归验收，不会关闭。

## 10. 相关文档

- [Plant 详细验收矩阵](QuadPlant-test-plan.md)
- [系统级目标验收矩阵](FlightSIM-test-plan.md)
- [实现状态](../IMPLEMENTATION_STATUS.md)
- [数据与依赖锁](validation/matlab_acceptance_manifest.json)
- [问题闭环规范](quality/ISSUE_WORKFLOW.md)
- [问题关闭清单](quality/ISSUE_CLOSURE_CHECKLIST.md)
- [Agent 操作总指南](AGENT-操作指南.md)
- [项目运行说明](../README.md)
