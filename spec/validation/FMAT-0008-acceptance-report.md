# FMAT-0008 验收报告：ARM_INITIAL_CONTROL_REFERENCE_RACE

- 分支：`optimize/sil-physical-parameter-alignment`
- 基线：`c5da00a8133a4cf675c313d6e743c876dedb3fae`（起始）→ 本报告对应 `3458546`
- 状态：**FIXED_WAITING_RETEST**（Issue 不关闭）
- 结论：本 Issue 描述的三个缺陷已修复并有证据；全部 12 项验收未全绿，阻塞在第 7 项之后的 Plant P-07（本分支新增测试，与本 Issue 主题无关，建议单独立项）。

## 1. 已修复缺陷

### 1.1 ARM 时首次控制参考竞态（本 Issue 主项）

现象：ARM 帧即锁存 `FAILSAFE_TERMINAL`（Host MIL `first_terminal=5.020 s`，`decision=3 FORCE_SAFE_ACTION`，`reason=18`），全程零推力。

根因：`fms_failsafe_update()` 在 `fms_permit_tick()` 之前执行；ARM 时 `control_link_established=0`、`reference_rebind_until_us=0`，首个 Control 能力帧必然携带 `controllable_dof_mask=0`（Host MIL 实测 dof=0、health=DEGRADED），命中 failsafe 的「四自由度不全即 TERMINAL」判据。既有的绝对首参考窗 `first_reference_timeout_us`（100 ms）只保护 permit 路径，永远来不及生效。

修复：`operator_authority.c` 新增 `fms_first_reference_pending()`，在「已 ARM 且控制链路未建立且仍在首参考窗内」时，不对尚未产出的控制参考上锁；故障等级≥3、执行器故障、control health=FAILED、姿态丢失仍立即 TERMINAL；链路建立后窗口永不生效；不延长超时、不屏蔽 TERMINAL、不放宽 permit。

测试：`tests/flight_management/test_m4_main.c` 新增 6 项（ARM 帧部分 DOF 不上锁、窗口内签署、超窗禁止输出、已建链后能力丢失仍 TERMINAL、过期参考不得签署、撤销水位跨重绑定）。M4 主机套件 `checks=993 failures=0`；把修复临时回退后前两项共 4 条断言失败，证明测试确实咬住该缺陷。

### 1.2 着陆链路（AUTO_LAND 模式与下探）

现象：AUTO_LAND 阶段控制能力掉到 `dof=0`，17.98 s 锁存 TERMINAL；此前着陆在 Home 平面上方悬停，LandDetector 永不宣告 LANDED。

根因一：`fms_guidance_mode()` 把 AUTO_LAND 落到 default（TRAJECTORY），而 `controller.c` 的着陆校验要求 `operation==LAND && guidance_mode_code==ALT_HOLD`，导致 MPC 追踪不可达的地面以下目标。

根因二：引导把着陆目标精确钳在 Home 平面；竖直估计相对机体存在漂移时，机体停在着陆面上方，接触判据（`gap ∈ [-20 mm, +1 mm]`）永不闭合。

修复：AUTO_LAND/EMERGENCY_LAND 发布为 `PRODUCT_GUIDANCE_MODE_ALT_HOLD`（走 `guidance_build_vertical_land` 与姿态/高度内环）；两条着陆路径（`pilot_and_landing.c` 与 `mission_trajectory.c`）在未 LANDED 时以 `GUIDANCE_LANDING_PROBE_M`（0.25 m）穿过 Home 平面下探。新增 M5 单测 `landing_reference_probes_below_home`，M5 套件 `checks=9515 failures=0`。

### 1.3 MIL 场景时序（验收数据错误，非产品缺陷）

现象：TAKEOFF 永远被拒 `reason=5`（`land != LANDED`），DISARM 永远被拒 `reason=11`。

根因：默认命令带 `[8000 8200 24000 48000]` 在 ARM ACK（5.02 s）之前就发出 TAKEOFF（4.1 s），该脉冲被拒后再无重发；DISARM 在 23.0 s 只打一次，此时 LANDED 的 2 s 驻留仅累计约 0.7 s，被拒后 FMS 一直重放缓存 ACK。

修复：命令带改为 `[8400 12000 28000 50000]`（4.2 / 6.0 / 14.0 / 25.0 s），并同步 `spec/validation/matlab_acceptance_manifest.json` 与 `spec/MATLAB-验收与结果提交.md` §3.1。

### 1.4 ExtINS 外部导航回放

现象：`Flight:ExternalReplay`，ExtINS 侧 `nav.valid_mask` 整轮为 0，`runtime_data.nav` 从未写入。

根因：`feed_sensors()` 用 `FMT_IMU_VALID` 门控 IMU 注入，但录制传感器带的有效位只在**奇数行**置 IMU 位（偶数行恒为 14），而该馈送运行在 1 ms 网格、正好对齐偶数行，于是 `inject_imu()` 从未执行，`estimator_push_imu/update` 从未被调用。

修复：外部导航模式不再用有效性位门控 IMU 注入（该模式下 IMU 仅用于驱动估计器节拍，导航是注入的）。

## 2. 验收矩阵

| # | 项目 | 结果 | 证据 |
|---|---|---|---|
| 1 | GNSS Origin Reset | PASS | `mil_diagnostics.json` |
| 2 | PreArm REJECT → READY | PASS | 同上 |
| 3 | ARM | PASS（5.220 s，ack=3） | 同上 |
| 4 | 首次 Control Reference | PASS | permit=CONTROL_ACTIVE |
| 5 | CONTROL_ACTIVE Permit | PASS | `mil_diagnostics.json` |
| 6 | M7 COMMITTED Receipt | PASS（`commit_valid=1`，最大推力 16.425 N） | 同上 |
| 7 | 2 m 起飞 | PASS（最大高度 2.098 m） | `matrix` 统计 |
| 8 | 稳定悬停 | PASS（≈2.48 m 高度保持） | 诊断时序 |
| 9 | 降落 | PASS（LAND ack=1，落到地面） | 命令历史 |
| 10 | DISARM / LOCK | PASS（26.020 s，ack=3，arm=0） | 命令历史 |
| 11 | DataSIM 回放 | PASS | `Flight:SensorReplay` |
| 12 | ExtINS 回放 | PASS（本报告前修复） | `Flight:ExternalReplay` |
| — | 源数据指纹 | 可用 | `7c514e63032674fb7e299682a2ba5f3e9b96c26cfef902fe33de62512bdc2937` |
| — | 后续组件门（Plant P-07 之后） | **逐个独立执行后全部 PASS**（见下） |

独立执行结果（绕过 `verify_plant_open_loop` 的 P-07 断言，其余门逐个 `feval`）：

```
verify_time_service_sync PASS   verify_gnss_time_recovery PASS   verify_rectime_time_mapping PASS
verify_parameter_view    PASS   verify_osqp_gate          PASS   verify_execution_gate      PASS
verify_truth_isolation   PASS   verify_rate_pid_transaction PASS verify_pid_allocator_feedback PASS
verify_actuation_components PASS  verify_sensor_event_timing PASS
```

因此整条验收链上**唯一失败点是 Plant P-07**；其余 MIL、回放、指纹与全部组件门均为绿。

## 3. 剩余阻塞：Plant P-07（建议单独立项）

`tests/verify_plant_open_loop.m` 的 P-07 杆臂运动学断言失败（该段落是本分支 Plant 验证重构新增，`origin/main` 上不存在）：

```
accel err=3.895e-02  pos err=0.000e+00  vel err=0.000e+00
got=[0.438949 -0.00155877 -9.80665]  expected=[0.4 0 -9.80665]
```

已排除：参数读取（天线位置/速度精确通过）、安装矩阵（实测单位阵，`MᵀM·ideal` 与理论一致）、偏置/刻度/噪声（测试已清零）、模型链路附加环节（`FMT_PlantSensors` 仅 1 个 S-function + 2 inport + 1 outport）。

**关键反转（已两次修正）**：同一工况、同一参数下，结果随**构建**变化：

| 构建 | 结果 |
|---|---|
| 带临时 `fprintf` 诊断的 mex | `ideal = measured = [0.400000, 0, -9.806650]`（断言期望值） |
| 干净源码重建的 mex | `[0.438949, -0.001559, -9.80665]` |

同一 MATLAB 会话内前后两次探针结果一致（`0.438949` ↔ `0.438949`），说明**不是测试顺序/状态泄漏**；而同一源码在不同构建下数值不同，属于构建相关的数值异常（未定义行为嫌疑）。四组对照（杆臂 0/0.1 × 角速度 0/2）显示偏差恒为 `ω² × 9.74 mm` 的等效杆臂，但该量既不在传入参数、也不在任何打印的中间量中（`lever_imu`、`centripetal_imu`、`accel_cg_ned`、安装矩阵均与理论一致）。

已尝试但受阻：以 `mex -O0` 单独重编该 S-function 对比优化级别影响，`mex` 报错未能完成；需改用其它手段（GCC 侧 `-O0`/sanitizer 构建、或脱离 Simulink 的纯 C 运算主体测试）继续定位。

该缺陷与 FMAT-0008 主题无技术关联，建议单独立项（例如 FMAT-0009：Plant SensorKinematics 加速度通道构建相关数值异常）。

## 4. 交付物索引

| 项目 | 位置 |
|---|---|
| Flight 修复 | `b8ae3ed`（failsafe）、`841478a`/`0851021`（着陆下探）、`b33b58e`（AUTO_LAND 模式） |
| Draft PR | hujunjie-hub/Flight#3（draft，未合 main） |
| Flight_Matalab | `139646f`、`a016d48`、`92eb036`、`e4b55e8`、`86c128f`、`53f2a7b`、`292f59b`、`3458546` |
| RUN_ID | `20261110T081853514Z_324d166` |
| ZIP | `work/validation/archives/20261110T081853514Z_324d166.zip`（22 个证据文件 + `run_manifest.json`，共 23 个条目） |
| ZIP SHA-256 | `bfd3a522112239396cc60fa95dc9b5e945e35303c6ef4e9b44e128aed2a8e00e` |
| 源指纹 | `7c514e63032674fb7e299682a2ba5f3e9b96c26cfef902fe33de62512bdc2937`（较早一轮为 `275e8374…`） |
| FMS 单元测试报告 | Flight `tests/flight_management` 主机套件输出（993 checks / 0 failures） |
| M5 单测 | Flight `tests/guidance` 主机套件（9515 checks / 0 failures） |

## 5. 复现方式

```powershell
# 同级 Flight 仓库切到 fix/fmat-0008-first-reference-race
cd E:\Flight\Flight_Matlab_Test
matlab -batch "cd(pwd); addpath('tools'); addpath('work'); run_acceptance"
pwsh -File .\tools\archive_validation_run.ps1
```

预期：MIL/DataSIM/ExtINS 通过并产出带源指纹的 ZIP；随后在 Plant P-07 处失败（与本 Issue 无关，见 §3）。
