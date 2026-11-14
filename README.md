# Flight_Matalab

> GitHub 仓库：`hujunjie-hub/Flight_Matlab`。当前唯一开发/验收分支为 `main`；不要从旧开发分支拉取代码。MATLAB 本地完整验证步骤、问题登记方式和交付文件清单见 [本地 MATLAB 验证交接说明](spec/validation/LOCAL_MATLAB_HANDOFF.md)。仓库名与 MATLAB Project 文件名存在历史拼写差异，工程文件仍为 `Flight_Matalab.prj`。

首次同步后，完整入口会先重建同级 Flight Host SIL 并重新记录 flight_baseline.json，随后执行契约头、OSQP、KF-GINS 和 SIM_ONLY 输入预检；预检不通过时停止后续 MATLAB 编译/仿真。不要在首次重建前单独运行 verify_inputs.py。操作步骤见上方本地验证交接说明。

## 一键本地验证

在 Flight_Matlab 仓库根目录打开 PowerShell 7，只需复制执行这一条命令：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\run_local_validation.ps1
```

脚本自动同步 Flight_Matlab/main 与 Flight/main，运行 MATLAB 完整验收、生成不可覆盖归档，并在 ARM/Host 工具链可用时完成 FMAT-0018 ABI 检查。最后只需交付 `work/validation/archives/<RUN_ID>_DELIVERY.zip` 和同名 `.sha256` 文件；总包还包含本轮验收 manifest 和状态摘要。遇到本地未提交修改时脚本会停止，不会 reset/clean。总包生成后，MATLAB/组件/ABI 失败会返回非零退出码；`PARTIAL_PASS` 仍是部分通过，不等于完整 PASS。当前 main 的完整本地复测状态为 `NOT_RUN`。详细行为见 [一键本地验证交接说明](spec/validation/LOCAL_MATLAB_HANDOFF.md)。

本工程使用同级 `../Flight` 的现行固件作为飞控实现来源。三个入口共用 `FMT_FlightCore`，通过 Windows Host SIL 运行生产任务和 M2～M7 中间件，包括 KF-GINS、FMS、制导、控制、OSQP 和执行器保护。飞控使用 Flight 的 Host SIL 默认配置和运行参数，执行器设备端落在内存记录桩。

| 模型 | 运行方式 |
| --- | --- |
| `simulation/FMT_DataSIM.slx` | 回放标准工程量传感器与指令，由固件 KF-GINS 计算导航；适合比对记录与控制输出 |
| `simulation/FMT_MILSIM.slx` | 连接原生 RK4 四旋翼对象，产生模拟传感器；M7 已提交且许可仍有效的四路推力闭合回路 |
| `simulation/FMT_ExtINS_DataSIM.slx` | 回放外部导航快照和能力消息，在 M3 输出边界代入；沿用固件 FMS、制导、控制和执行器保护 |

## 运行

打开 `Flight_Matalab.prj`。默认闭环命令为解锁、起飞至 2 m、降落和上锁。两种回放共用默认 MIL 记录，其中 ExtINS 使用同一次 MIL 运行录制的 KF-GINS 导航作为外部输入。若刚从 Git 更新了代码或 SIM_ONLY 配置，不要沿用旧 DLL/MEX 和旧验证报告；先按下文重建，再执行 `run_component_checks` 刷新当前源代码证据。可在 MATLAB 执行 `verify_flight_entries` 复核三个入口。

清理 `work/`、换机或更新同级 Flight 时间服务源码后，在项目根目录重建 Windows Host SIL 运行库；该步骤也会刷新 `flight_baseline.json`，锁定 `systime.c` 和上游时间服务回归源。默认编译器路径为 `D:\STM32CubeCLT\mingw64\bin`，可通过 `-GccDir` 指定兼容的 MinGW 目录。不要在旧 baseline 尚未包含 `tests/time/test_time_service.c` 时单独运行 `build_native_kernels`。

```powershell
pwsh -File tools/build_flight_runtime.ps1
```

然后在 MATLAB 打开项目，确认 `mex -setup C` 已配置，执行以下命令。源代码、接口或配置有更新时，建议直接执行 `run_component_checks`；该入口会重建运行库、MEX、参数字典和受影响模型，并保存本次验证报告。

```matlab
build_flight_mex
verify_flight_entries
```

需要重新生成模型图时，加载 Simulink Agentic Toolkit 并执行 `build_flight_models`。使用 `verify_flight_entries(true)` 可从当前 MIL 重建默认回放数据。当前工程的原生 PID、分配、帧量化和 G1/G2 模型作为独立试验保留。运行这些旧组件检查前，用 `python -B tools/prepare_sources.py` 恢复其附加参考依赖，并在 MATLAB 执行 `build_native_kernels`。

## 输入和输出

三个入口使用 500 μs 离散基步和正常仿真模式。固件 Host SIL 在每 1 ms 调用传感器与执行器任务，每 4 ms 调用通信，每 20 ms 调用 FMS 与 MPC，每 100 ms 调用监督任务。输出包含当前提交推力、飞控诊断和已发布导航，均在下一基步可读。当前 DLL 以单实例运行，每个 MATLAB 进程一次仿真一个入口。

- `SensorFrame` 为 18 元素 double，依次为 IMU 处 FRD 角速度 rad/s、IMU 处 FRD 比力 m/s²、GNSS 天线 NED 位置 m、GNSS 天线 NED 速度 m/s、FRD 磁场 μT、相对气压高度 m、有效位掩码和接地状态。四组有效位依次为 1、2、4、8，分别代表 IMU、GNSS、磁力计和气压计；接地状态 0、1 分别代表空中和接地，其余值表示未知。由输入数据标明缺测，适配器按固件主机夹具节拍提交样本。
- `OperationRequest` 为 2 元素 double，即产品指令码及起飞高度 m。单步脉冲提交一次，0 表示本步没有指令。默认用 1、3、4、2 分别完成解锁、起飞、降落、上锁。
- `ExternalNavFrame` 与 `PublishedNavFrame` 为 `uint8`，是同一主机构建的 `NavigationSnapshot` 和 `NavigationCapability`，顺序与时间戳均保留。宽度由 `config/flight_baseline.json` 提供。输入必须使用与本次构建匹配的接口契约版本、时钟域、历元和有效期。ExtINS 的 IMU 有效样本驱动生产传感器任务发布导航。默认文件记录当前 Host SIL 的配对结果。
- `CommittedThrustN` 顺序沿用 `Flight/config/vehicle_model.yaml` 的左前、右前、右后、左后。只有有效的 M7 提交和匹配许可才产生推力。
- `FlightStatus` 顺序为固件单调时间 μs、预检、解锁状态、飞行模式、故障保护、许可范围、M7 回执、提交有效、最近请求 ID、应答状态、应答原因、导航有效位、NED 位置三轴、NED 速度三轴、导航状态、控制状态、规划状态、MPC 更新计数、执行器写入计数、主机夹具失败计数。

## Plant 模型边界与验证

- 质量、惯量、电机位置、偏航符号、推力上下限和电机时间常数来自同级 `Flight/config/vehicle_model.yaml`；SIM_ONLY 配置只保留推力系数、阻力、接触和 Origin 等仿真专属参数。
- PlantParameters 固定为 26 项，SensorParameters 固定为 19 项，SensorModelParameters 固定为 54 项；前两者分别包含完整 3×3 对称正定惯量矩阵、Earth-rate/Coriolis 和 IMU/GNSS 杆臂参数，第三者承载安装矩阵、残余 bias/scale、各传感器噪声 STD 与随机种子。另生成 SensorTimingParameters（10 项）保存各传感器采样周期、传输/管线延迟和时间不确定度，由 MIL Host SIL 运行时的独立事件队列消费；当前 Flight 合成惯量恰好为对角矩阵。第一版地面摩擦系数明确设为 0，不引入未验证的水平接触力。分配器使用从 Flight 电机几何推导的 4×4 effectiveness/inverse 矩阵。
- Plant S-Function 对状态、参数、wrench、环境和输出做 fail-closed 检查；完整对称正定 3×3 惯量由 Cholesky 求解，非法环境开关、电机效能越界、非对称/非正定惯量和非有限状态均拒绝。
- MIL 传感器模型已加入固定 N0 Earth-rate/Coriolis 项、CG→IMU 杆臂加速度、IMU→GNSS 天线位置/速度杆臂，并屏蔽首个无法差分的 IMU 样本。P-09 已加入按 seed/source/sample-index/axis 派生的无状态高斯噪声、IMU/MAG 安装矩阵、残余 bias/scale 和 GNSS/气压噪声；同 seed 可复现，噪声索引不依赖 RK4 调用次数。P-10 的第一阶段已在 MIL Host SIL 运行时接入 IMU/GNSS/MAG/Baro 多速率事件队列，分别保留 sample/capture/arrival/release 时间，arrival 是物理传输完成时刻，release 是固定步长队列实际交付固件的时刻；统计 generated/suppressed/released/accepted，并检查丢样序号缺口、队列守恒、500 μs 固定步和固件样本有效期。GNSS PVT 当前使用本地 monotonic epoch。`verify_time_service_sync` 以 MEX 编译真实 Flight `systime.c` 并运行上游时间服务测试；`verify_gnss_time_recovery` 进一步编译真实 TimeService、GNSS sample normalization/filter/calibration 和 Flight 的 GNSS/PPS/UTC 丢失恢复测试；`verify_rectime_time_mapping` 则编译真实 UM982 `unicore_ascii.c`，验证 RECTIMEA 字节帧、CRC、GPS/UTC 日历交叉检查以及与有效 PPS 边沿配对后的 UTC mapping。三者均不复制固件算法，PPS 输入仍为合成 capture event；Host MIL 的 `sil_flight.c` 仍将时间服务 API stub 为 `STATUS_NOT_READY`，物理 TIM2 ISR 和真实 UART/DMA 接入尚未完成，故 P-10 整体仍为 PARTIAL。
- 完整组件检查入口为 `run_component_checks`：它先执行输入预检、重建原生 MEX 内核、生成数据字典参数，刷新独立传感器探针及 MILSIM 的双参数绑定，再运行参数视图、Plant、真值隔离、控制和执行器组件测试。若只检查 Plant，可依次执行 `build_native_kernels`、`generate_parameters`、`build_plant_models(8)`、`verify_parameter_view`、`verify_plant_open_loop`、`verify_truth_isolation`；`verify_plant_open_loop` 会自动调用 `verify_sensor_event_timing`；`verify_time_service_sync`、`verify_gnss_time_recovery` 和 `verify_rectime_time_mapping` 分别验证 Flight 时间服务核心、GNSS 失效恢复以及真实 RECTIMEA 解析到 UTC mapping 的核心路径。若只调试事件队列，可单独执行 `verify_sensor_event_timing`；若只检查时间/GNSS 核心，可在 `build_native_kernels` 后分别执行这三个验证入口。Plant 报告当前必须保持 PARTIAL；P-07/P-08 杆臂运动学、静止 IMU、Earth-rate/Coriolis 已有脚本，P-09 seeded noise/bias/scale 测试已加入；P-10a 队列子项和 P-10b TimeService 核心已有独立测试，但 Host MIL 的 TIM2 capture/UM982 RECTIME 端到端链仍待实现。P-14 由 `verify_truth_isolation` 独立检查，并纳入 `run_component_checks`。以上脚本尚未在本次环境中执行 MATLAB/Simulink 验证。

## 基线与边界

`config/firmware_sources.json` 指向当前固件配置、合同和 OSQP 目录，`config/flight_baseline.json` 记录固件输入 SHA-256 和回放 ABI。四旋翼质量、转动惯量、旋翼位置、偏航符号、推力上限和电机时间常数由 `Flight/config/vehicle_model.yaml` 提供。空气阻力、地面接触、转速到推力系数及模拟传感器仍为 SIM_ONLY 参数。固件调度沿用上游 Host SIL 顺序，硬件中断、RTOS 实时性、原始传感器字节、PPS、实体 DShot、实飞和 HIL 链路属于不同的验证范围。现有 `spec/` 保留原生组件设计与验收记录。

### 仿真参数一致性

`generate_parameters` 将 Flight 的电机坐标、偏航力矩系数和动力学参数写入 `Flight_Parameters.sldd`。本地数值分配器使用从 Flight 四个电机坐标和偏航力矩系数推导的 4×4 effectiveness 矩阵及其逆矩阵，并在运行时检查矩阵互逆；不再假定特定电机排序。MIL 传感器的 NED 磁场由 `config/SIM_ONLY/QUAD_X4/sensor_alignment.yaml` 提供。修改磁场或物理配置后，重新执行 `build_flight_mex` 和 `build_flight_models`，再运行参数与组件检查。


## MATLAB 测试与验收

当前 `main` 分支的唯一自动化验收入口为 `run_component_checks`。本地运行、Diary 保存、归档、Issue 登记和必交文件清单以 [本地 MATLAB 验证交接说明](spec/validation/LOCAL_MATLAB_HANDOFF.md) 为准。该入口会重建 Host SIL/MEX/模型、刷新 MIL 回放数据，并运行当前已实现的组件与三入口回放测试。测试数据集、每项验收阈值、必需报告、已知缺口和结果提交方式统一见 [MATLAB 仿真测试数据集与验收标准](spec/MATLAB-验收与结果提交.md)。本地完整验收和交付统一执行 `pwsh -NoProfile -ExecutionPolicy Bypass -File .\\tools\\run_local_validation.ps1`；该脚本会自动归档并生成单一 `_DELIVERY.zip`，无需再单独运行 archive_validation_run.ps1。问题登记、状态流转和关闭规则见 [问题闭环规范](quality/ISSUE_WORKFLOW.md)。不要使用旧报告或静态审查结果代替本次 MATLAB 运行结果。
