# 实施状态

当前交付范围为 **Flight 固件 Windows Host SIL**。现行合同为 Schema 6.0、Product/Port `0x00010906`。三个顶层模型和共享飞控模型已生成并注册到 MATLAB Project。下表是此前记录的 Host SIL 基线证据；本轮更新了 MIL 传感器事件队列、参数预检和测试脚本，当前分支尚未在 MATLAB/Simulink 重新执行完整验证，相关 manifest 已标记为 STALE_REQUIRES_RERUN。

| 范围 | 实测结果 |
| --- | --- |
| Flight 固件基线 | 上游 Host SIL 通过 3,151 项检查，配置及源码共 457 个文件完成 SHA-256 核对 |
| 公共类型 | 重新从现行固件头文件生成 106 个值类型 Bus |
| MILSIM | 26 s 闭环，完成解锁、2 m 起飞、降落、上锁；实际最高 1.986 m，最终速度接近零 |
| DataSIM | 回放 MIL 标准工程量传感器与指令，诊断和四路提交推力逐样本一致 |
| ExtINS DataSIM | 在 M3 输出边界回放保存的导航快照和能力，飞行状态和四路提交推力逐样本一致 |
| 冷启动 | 独立 MATLAB 进程中，三个入口的默认输入冒烟和完整复跑均通过；MATLAB Project 9 项检查通过 |
| 缺测保护 | DataSIM 全传感器缺测时，解锁指令产生的提交推力持续为零 |

`implementation_manifest.json` 记录模型、录制数据、源码和仿真证据的完整性信息。单点接地在上锁后会倾倒，最终 SIM_ONLY 物理对象采用四点接地与正则化摩擦。ExtINS 的默认录制来源为 MIL 中的固件 KF-GINS。当前证据覆盖主机仿真与合成输入，STM32 时序、HIL 链路、实体执行器和实飞另行验证。



## Plant 物理模型第二阶段（代码状态）

以下是独立的 Plant 算法验证代码状态，不计入上表已实测通过的 Host SIL 结果。当前尚未在 MATLAB/Simulink 环境运行本阶段测试。

- Plant 参数合同扩展为 26 项：质量、完整 J(:) 3×3 惯量、k_f、电机时间常数、阻力、角阻尼、地面接触、重力和摩擦系数。
- 刚体角运动使用完整 J·omega、omega×(J·omega) 和 Cholesky 求解 J*alpha=rhs；参数入口拒绝非对称或非正定惯量。
- Plant S-Function 对状态、环境、wrench、参数和输出做有限值检查；ground/drag 开关严格为 0/1，rotor_effectiveness 限定 [0,1]。
- 第一版地面摩擦系数明确设为 0；增加静态 mg/k 支撑、无水平摩擦、FRD/NED 变换、风阻、250 μs 独立 RK4 参考和输入拒绝测试。
- 传感器参数合同增加 SensorModelParameters（54 项），包括 IMU/MAG 安装矩阵、gyro/accel/mag 残余 bias/scale、IMU/MAG/GNSS/Baro 噪声 STD 和固定随机种子；随机数由 seed/source/sample-index/axis 无状态派生，不随 RK4 子步或调用顺序变化。SensorTimingParameters（10 项）已接入 MIL Host SIL 独立事件队列：IMU/GNSS/MAG/Baro 分别按配置周期采样，保留 sample/capture/arrival/release 四个时间，区分物理到达和 500 μs 队列实际交付时刻；队列统计 generated/suppressed/released/accepted，并验证缺测导致的序号缺口、计数守恒、队列容量和固件样本有效期。
- 当前代码覆盖 P-01～P-09、P-11～P-13、P-15～P-21；P-07/P-08 覆盖杆臂运动学和静止 IMU，P-09 已加入相同 seed 重复性、不同 seed 独立性、IMU 噪声 STD 95% 卡方区间、轴间相关性及 bias/scale 注入测试。P-10a 的多速率队列、sample/capture/arrival 和缺测计数已有独立 `verify_sensor_event_timing`；P-10b 的真实 Flight TimeService 核心由 `verify_time_service_sync` 回归，GNSS PVT 失锁与 UTC/PPS 独立失效由 `verify_gnss_time_recovery` 回归，真实 UM982 `unicore_ascii.c` 的 RECTIMEA→PPS 配对 UTC mapping 由 `verify_rectime_time_mapping` 回归；但 Host MIL 的物理 PPS capture、UART/DMA 和 `sensor_gnss_poll` 端到端链仍未接入。`pps_backend` 明确为 `DISABLED_LOCAL_MONOTONIC`，因此 P-10 整体仍为 PARTIAL。P-14 已由 verify_truth_isolation 实现并纳入 run_component_checks。

本阶段需在用户 MATLAB 环境执行 run_component_checks；该入口会先运行输入预检、重建 build_native_kernels、生成参数字典，再执行 verify_parameter_view、verify_plant_open_loop（内部调用 verify_sensor_event_timing）及已实现组件检查。也可单独执行 build_native_kernels、generate_parameters、verify_parameter_view 和 verify_plant_open_loop；后者会调用 verify_sensor_event_timing。需要只调试队列时可单独执行 verify_sensor_event_timing。必须保存实际运行报告、MATLAB 版本、求解器与模型 Hash。Plant 报告必须保持 PARTIAL，不能解释为完整物理模型验收、HIL 实时性 PASS 或实机飞行放行。

## P-10b 时间服务核心回归（代码状态）

- 新增 fmt_time_service_probe MEX wrapper，直接编译同级 Flight/sensor_device/time_base/systime.c，并调用上游 Flight/tests/time/test_time_service.c，不复制或重写 TimeService 算法。
- 新增 fmt_gnss_outage_probe MEX wrapper，编译同级 Flight 的 systime.c、sensor_sample.c、sensor_filter.c、sensor_calibration.c，并调用 tests/drivers/test_gnss_outage.c；覆盖 GNSS 无 Fix/PVT 过期、PPS 与 UTC 分别失效、Holdover、PPS 重捕获和坏边沿拒绝。
- 新增 fmt_rectime_time_probe MEX wrapper，编译真实 Flight `unicore_ascii.c` 与 `systime.c`，构造有效/损坏 RECTIMEA 帧，验证 CRC、GPS week/TOW 与 UTC 日历交叉检查、receiver accuracy、output delay、最新 PPS 选取、UTC mapping 锁定以及错误 PPS 配对拒绝。
- build_native_kernels 会构建三个 MEX；run_component_checks 会执行 verify_time_service_sync、verify_gnss_time_recovery 和 verify_rectime_time_mapping，分别保存三份独立 JSON 报告。
- 上游测试覆盖单调时间映射、PPS 周期门限/频率锁定/失锁 holdover、UTC observation 必须与 PPS 配对、UTC 映射不确定度、外部时钟映射和 time_epoch 不连续拒绝。
- 三组回归使用合成 PPS capture event 与确定性 tick source；RECTIME 测试直接调用真实字节解析器，GNSS recovery 测试调用真实 sample normalization/filter。它们验证算法与解析核心，不证明 TIM2 capture ISR、UART/DMA 传输、RTOS 任务调度和 PPS/UTC 在 MILSIM 中端到端运行。当前 Flight/tests/simulation/sil_flight.c 的时间服务接口仍为 STATUS_NOT_READY stub，故 P-10 整体保持 PARTIAL。
- MATLAB/MEX 编译与执行尚未在本次环境运行；本阶段代码状态不能写成实测 PASS。


## 2026-11-09 Plant 传感器采样间隔修正

- 修正 IMU 运动学历史状态：只在配置的 IMU sample epoch 更新上一采样速度/角速度，差分时间使用两个真实 IMU sample epoch 之间的时间，不再误用 500 μs Plant 基步。
- P-07 增加 2 ms IMU 周期、非恒定线加速度/角加速度与 jerk 的回归夹具，并检查非采样时刻 IMU validity bit 必须关闭。
- 本次为代码与测试夹具更新；当前环境未执行 MATLAB/Simulink/MEX。必须在 MATLAB 环境重新运行 `run_component_checks`，此前验证证据继续保持 STALE，不能标记为 PASS。


## MATLAB 验收依据（2026-11-09）

当前分支的测试数据集、运行入口、逐项阈值、报告清单和已知未实现范围统一由 [MATLAB 仿真测试数据集与验收标准](spec/MATLAB-验收与结果提交.md) 及其机器可读清单 `spec/validation/matlab_acceptance_manifest.json` 管理。`run_component_checks` 已作为完整验收入口：重建依赖后运行 `verify_flight_entries(true)` 刷新 MIL 回放数据，再执行已实现组件 gate 并生成最终输入指纹。当前预期仍为 `PARTIAL_PASS`，不能把 P-10 Host MIL PPS/RECTIME 端到端缺口解释为通过。


## 2026-11-09 MATLAB 验收运行记录（FAIL）

- 仓库/分支：`hujunjie-hub/Flight_Matalab` · `optimize/sil-physical-parameter-alignment` · HEAD `74104d8`，工作区干净。
- 环境：MATLAB `26.2.0.3433840 (R2026b) Update 1`，Windows x64；Host SIL 用 MinGW-w64 GCC `D:\STM32CubeCLT\mingw64\bin`；Flight 上游 `edf32b4e39cdae014aa76870dc821882807a6905`。
- 入口与结果：`run_component_checks`，**FAIL**。第 1 步 Host SIL 构建失败（`Flight:RuntimeBuild`，`parameter_store.h` 未找到）。`build_native_kernels` 及之后全部组件 gate、MIL/DataSIM/ExtINS 回放、`current_source_fingerprint.json` 均为 NOT_RUN 或缺失，不得视为通过。
- 证据归档：`work/validation/archives/20261109T115735527Z_74104d8.zip`，SHA-256 `ae8e3085a0aa61e7e21c44ceea5b38cf3188528f0144366bd4567d2b6a807128`。
- 问题台账：GitHub Issues 是唯一台账，本轮登记 FMAT-0002～FMAT-0010，其中 FMAT-0007 与构建阻断无关、FMAT-0008/FMAT-0009 需在构建阻断解除后按新 RUN_ID 复现。

| ID | 级别 | 组件 | 摘要 |
|---|---|---|---|
| FMAT-0002 | S1 | BUILD | adapter 编译缺少 `middleware/param` 头文件路径 |
| FMAT-0003 | S1 | BUILD | `external_dependencies.lock.json` 三个契约头文件哈希过期 |
| FMAT-0004 | S1 | SENSOR | 适配器在 `double` 数组上按位或，MEX 编译失败 |
| FMAT-0005 | S1 | OTHER | `max(...,'all')` 在 R2026b 非法（5 处） |
| FMAT-0006 | S1 | OTHER | `removeEntry` 在 R2026b 已移除 |
| FMAT-0007 | S2 | OTHER | `verify_truth_isolation` 期望块名与 `FMT_MILSIM.slx` 不一致 |
| FMAT-0008 | S1 | FMS | MIL 全程未解锁、无推力、无起飞，导航有效位恒 0（待复现） |
| FMAT-0009 | S1 | PLANT | P-07 IMU 加速度差分仍用 Plant 基步（待复现） |
| FMAT-0010 | S1 | BUILD | `config/flight_baseline.json` 与 `../Flight` 不符（9 缺失/58 漂移） |

- 阻断链：FMAT-0002 → FMAT-0003 → FMAT-0010 → FMAT-0004 → FMAT-0005 → FMAT-0006；解除后才可能复现 FMAT-0008、FMAT-0009。
- 本轮未修改代码；此前一轮的本地修补仅保存在 `git stash` 与 `work/local_r2026b_fixes_backup.patch` 中，未提交、未推送。


## 2026-11-09 23:41 MATLAB 验收运行记录（Host SIL 构建通过，预检阻断）

- 仓库/分支：`hujunjie-hub/Flight_Matalab` · `optimize/sil-physical-parameter-alignment` · HEAD `3f885a9`（运行时的两项修补见下，本轮随代码提交）。
- 入口与结果：`run_component_checks`，**FAIL**。第 1 步 Host SIL 构建已通过：产出 `work/mex/fmt_flight_runtime.dll`（1,813,260 字节），上游 SIL 自测 `4147 checks, 0 failures`。运行停在 `build_native_kernels` 的输入预检（`tools/verify_inputs.py:82`，`Production header changed: middleware/contracts/contract_checks/algorithm_checks.h`），即 FMAT-0003。
- 证据归档：`work/validation/archives/20261109T154213789Z_3f885a9.zip`，SHA-256 `3bf083944271a32de3c0f922ba344f594bd863d3eb9a473fa43c4ef381a19454`。
- 本轮修复两项：
  - FMAT-0002：`tools/build_flight_runtime.ps1` 的 include 集增加 `middleware/param`，与 `Flight/tests/simulation/run_sil.ps1` 一致。
  - FMAT-0010：`config/flight_baseline.json` 不再手工维护，改由 `build_flight_runtime.ps1` 每次构建调用 `record_flight_baseline.py` 全量重生成；本次为 482 项 `sources_sha256`（含 `applications/tasks/` 下 13 项新子目录路径），`product_contract_revision=0x00010906`、`navigation_frame_bytes=360`。
- 仍未闭合：FMAT-0003（当前唯一阻断）、FMAT-0005（3 处 `max(...,'all')` 未改）、FMAT-0007（块名已改但比较串仍为 `/modelparams`、`/timingparams`）、FMAT-0008/0009（需构建阻断解除后复现）。


## 2026-11-09 23:59 MATLAB 验收运行记录（构建链全通过，MIL 不起飞）

- 仓库/分支：`hujunjie-hub/Flight_Matalab` · `optimize/sil-physical-parameter-alignment` · HEAD `f00f610`，运行前工作区干净；运行后仅构建产物（模型 `.slx`、`.sldd`）变化。
- 执行方式：`openProject('Flight_Matalab.prj')` → `flight_startup` →（Diary）`run_component_checks`，与验收文档一致。
- 结果：**FAIL**，但已越过全部构建与模型环节。
  - Host SIL DLL 构建通过；`verify_inputs` PASS（headers 10、OSQP 47、KF-GINS 54）。
  - `build_native_kernels`（全部 MEX 含 OSQP）、`generate_parameters`、`build_plant_models(8)`、`build_flight_models`（四个入口）、`build_actuation_components`、`build_pid_allocation_probe` 全部完成。
  - 停在 `verify_flight_entries(true)`：26 s MIL 跑满，`arm` 全程 0、提交有效 0 次、推力恒 0、最大高度 0.000 m，`Flight:MILTakeoff` 断言失败。
- 证据归档：`work/validation/archives/20261109T160227108Z_f00f610.zip`，SHA-256 `c76d955f507bb7415ae58efd808e5a0074e8aa3971491e9c77fa1be68787bd91`，7 个文件（含 `component_checks.json`、`input_preflight.json`、Diary、`firmware_sil.log`、`run_manifest.json` 和回放 MAT 副本）。
- 问题台账变化：FMAT-0002/0003/0004/0006/0010/0011 → VERIFIED；FMAT-0005/0007 → FIXED_WAITING_RETEST（本轮未执行到）；FMAT-0008 → REPRODUCED（干净树正式复现）；FMAT-0009 仍为 NEW（未执行到 Plant P-07）。
- 结论：当前唯一阻断是 FMAT-0008（MIL 未解锁、导航有效位恒 0），不是构建问题。
## 2026-11-10 00:43 MATLAB 验收运行记录（构建全通过，解锁仍被拒）

- 分支/HEAD：`optimize/sil-physical-parameter-alignment` @ `9e5048c`（8b1baa3 对齐 MIL 传感器采样历元与运行时释放时钟、9e5048c 增加 MIL 诊断），运行前工作区干净。
- 结果：**FAIL**，与上一轮相同阶段中止。构建链（Host SIL、`verify_inputs`、MEX、参数字典、Plant/Flight 模型）全部通过，`verify_flight_entries` 在 26 s MIL 后失败。
- 新证据：`MIL diagnostics: armed=0 commit_valid=0 max_nav_mask=0xD7 max_total_thrust=0.000 N max_motor_thrust=0.000 N last_request=2204 ack=0 reason=11`。导航有效位已从全 0 提升到 `0xD7`，但解锁请求仍为 `COMMAND_ACK_REJECTED`（ack=0）、reason=11，`arm` 恒 0。
- 断言变为 `Flight:MILArm`（此前为 `Flight:MILTakeoff`）：解锁这一环先失败，尚未到起飞判定。
- 证据归档：`work/validation/archives/20261109T164306449Z_9e5048c.zip`，SHA-256 `afa63f983668634ac59e2932baa213903a2954d5bf61149c2719dd5f7e3cdf9f`。
- 台账：FMAT-0008 追加本轮诊断证据，状态仍为 REPRODUCED；其余 Issue 状态不变。
## 2026-11-10 06:23 MATLAB 验收运行记录（PreArm 定位到水平位置有效性）

- 分支/HEAD：`optimize/sil-physical-parameter-alignment` @ `3280e6a`（新增逐指令 ACK/PreArm 诊断与 `mil_diagnostics.json`），运行前工作区干净。
- 结果：**FAIL**，仍在 `verify_flight_entries` 中止（`Flight:MILArm`）。构建链全通过。
- 关键证据（`mil_diagnostics.json`）：
  - `final_prearm_state=3`（REJECT）、`failed_mask=8`、`primary_reason=2`（PREARM_ITEM_FAIL）、`failed_count=1`。
  - 失败掩码 bit3 对应 `PREARM_ID_ESTIMATOR_POSITION`；`maximum_navigation_mask=0xD7` 中缺少 bit3 `NAV_VALID_HORIZONTAL_POSITION` 与 bit5 `NAV_VALID_HORIZONTAL_VELOCITY`，垂直位置/速度正常。
  - 四条指令 ack_state 均为 0（REJECTED）；解锁、起飞、降落三条 reason=2，上锁 reason=11。
- 结论：阻断点收敛为「水平位置有效性未发布」，与姿态/IMU/遥控/执行器无关。
- 证据归档：`work/validation/archives/20261109T222421249Z_3280e6a.zip`，SHA-256 `94c21e0edfa49672bd8b3623fe17ce5b9758d2ee2e84eab9604e91a7875dd69d`。
## 2026-11-10 09:00 MATLAB 验收运行记录（水平位置断言确认）

- 分支/HEAD：`optimize/sil-physical-parameter-alignment` @ `0dd4515`（5dfca7b 要求 FMS 有效控制许可与 M7 已提交回执，0dd4515 补充联合许可验收文档），运行前工作区干净。
- 结果：**FAIL**，仍在 `verify_flight_entries`；断言变为 `Flight:MILHorizontalPosition`（第 121 行）：“GNSS-assisted origin reset did not establish valid horizontal position.”
- `mil_diagnostics.json` 与上轮一致：`prearm_state=3`、`failed_mask=8`（ESTIMATOR_POSITION）、`primary_reason=2`、`max_nav_mask=0xD7`、四条指令 ack=0。
- 结论：上一轮推断的“水平位置有效性未置位”已由脚本专门断言确认，问题不在姿态/IMU/遥控/执行器，也不在采样历元。
- 证据归档：`work/validation/archives/20261110T010015204Z_0dd4515.zip`，SHA-256 `9ec6006bf11ec8455603da166f895acbca86484092a1e793695356336b2c5cb2`。## 2026-11-11 00:32 MATLAB 验收运行记录（M6 诊断通道 + P-10b 口径修复）

- 分支/HEAD：`optimize/sil-physical-parameter-alignment` @ `a5628f7`（Flight 上游 `a40c4b2`），`source_clean=true`，运行前后 commit 一致。
- 结果：**FAIL**，18 PASS / 1 PARTIAL（Plant）/ 1 FAIL。唯一 FAIL 是 `m6_jobs`；其余全部门通过，含新增的 `p10b_summary` 与 A-08 归档自测。
- M6 证据（逐 job，`m6_jobs.json` 488 条）：首个拒绝阶段 `RESIDUAL` 468 / `OK` 20；488 个 job 全部 `CONTROL_SOLVER_SOLVED`；primal residual median 3.0e-8，dual residual median **1.75e-3**、max 1.00e-2；独立约束违反 max 8.6e-4，推力超出恒 0；消费点 9760 中仅 80 采用（全部因 `expires` 过期），快照 `expires-sample` max 8000 µs、`expires-eval` max 5000 µs。
- 判别实验（已回退）：`eps_rel=0`（门限不动）→ solved 489/489、采用 1956/9780、MIL 最大高度 **0.242 m**，TAKEOFF 于 6.0 s 以 `reason=5`（`land != LANDED`）被拒。MPC−PD 逐轴差值上限 0.33/0.33/0.16 m/s²，说明失败来自地面段与起飞前置条件的耦合，而非控制量幅值。
- P-10b：PPS 21/1、RECTIMEA 21、GNSS 21、`utc_mapping_epoch=11`、`accepted_intervals=12`、不确定度 384,042 ns；失锁期 `utc_valid=0`、holdover 4.5 s、225,359,042 ns。顶层 `p10b_report.json` 现由本轮三份报告合成，不再硬编码 `NOT_RUN`。
- 其他修复：#16 归档分类新增 `pre_existing_local_change_modified_by_run`（本轮实测 5 个文件被归入该类别）；#15 `controller.c` 越界读改为两个 3 元素检查。
- 证据归档：`work/validation/archives/20261110T163238005Z_a5628f7.zip`，SHA-256 `307279fcdbd53ae111f8467276f8669db293f9d9683474fef8cd39199b978afc`。

**M7 Ground Stop（2026-11-11）**

- Flight 固件：`middleware/actuator/output_guard/actuator_guard.{c,h}`（`actuator_guard_ground_stop`、帧边界降推力分支、DISARMED latch、`thrust_to_code()` 统一映射）、`middleware/contracts/messages/common_messages.h`（`GroundStopCertificate`、stop code/速率/预算常量、`ACTUATOR_RECEIPT_ZERO_TARGET_APPLIED`）、`message_ids.h`（`MSG_GROUND_STOP_CERTIFICATE` = 56）、`tests/actuation/test_m7_main.c`（M7-11…M7-16）、`tests/actuation/run_host_tests.ps1`。
- Flight_Matalab：`tests/verify_actuation_components.m`（透出 ground stop 字段）、`external_dependencies.lock.json`（契约头哈希，旧值归档于 `config/dependency_history/607f4996….json`）、`config/flight_baseline.json`。
- 实测：M7 主机套件 230 checks / 0 failures；归零 40 帧、100,000 µs，受理到应用 100,500 µs ≤ 105,500 µs。
- 未覆盖：FMS 侧签发触发逻辑、真实 ESC 物理推力响应、PIL/HIL 与实机时序。
