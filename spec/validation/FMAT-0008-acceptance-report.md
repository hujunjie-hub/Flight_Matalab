# FMAT-0008 验收报告：ARM_INITIAL_CONTROL_REFERENCE_RACE

- 分支：`optimize/sil-physical-parameter-alignment`
- 基线：`c5da00a8133a4cf675c313d6e743c876dedb3fae`（起始）→ 本报告对应 `9169cb9`
- 状态：**FIXED_WAITING_RETEST**（Issue 不关闭）
- 结论：本 Issue 描述的三个缺陷已修复并有证据；12 项验收目标全部 PASS，`run_component_checks` 为 `PARTIAL_PASS`（Plant 门为设计内的 `PARTIAL`，全部 20 个 Plant 用例通过）。原先阻塞验收的 Plant P-07 已定位并修复，见 §3 与 [FMAT-0009](../quality/FMAT-0009-plant-sensor-accel-anomaly.md) §12。

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
| — | 源数据指纹 | 可用 | `857d6d6de3b39710b05aa0554d2fc13168a365782bd1e0ffce87270382b1bcd6` |
| — | `run_component_checks` 总体 | `PARTIAL_PASS`（1 个大项 `PARTIAL`：Plant 闭合环不在组件门内） | `component_checks.json` |
| — | 组件门逐项 | `flight_entries`/`time_service`/`gnss_time_recovery`/`rectime_time_mapping`/`parameters`/`osqp`/`execution`/`sensor_event_timing`/`truth_isolation`/`pid`/`pid_allocator_feedback`/`actuation` 全部 **PASS**，`plant` **PARTIAL**（20/20 用例通过） | 同上 |

`plant` 的 `PARTIAL` 是设计内取值：`plant_open_loop_report.json` 明确 `system_closed_loop=NOT_RUN`，闭合环由 `flight_entries` 覆盖。实测 20 个 Plant 用例（P-02…P-21）全部通过，包含修复后的 P-07 与 P-20。

## 3. Plant P-07 与 P-20：已定位并修复（FMAT-0009）

本轮将原「剩余阻塞」闭环，结论与证据见 [FMAT-0009](../quality/FMAT-0009-plant-sensor-accel-anomaly.md) §12，摘要：

- **P-07 根因**：`fmt_plant_sensors_sfun.c` 的 `mdlOutputs` 在同一个循环里既写 `accel_imu_body[i]`、又立刻读它的全部三个分量，`i=0` 时轴 1/2 尚未初始化 → 未定义行为。这解释了此前所有「跨构建不一致」：加一条 `fprintf` 就改变栈布局，MSVC 与 GCC 结果不同，UBSan 检测不到。
- **定量证明**：脱离 Simulink 的纯 C 复算（`work/p07_standalone/p07.c`）在 MSVC `/O2`、GCC `-O0`、GCC `-O2` 下都给出缺陷写法 `1.307812563`/`1.307812724`（与 mex 实测一致）、修复写法 `1.315879362`（与解析参考差 `2.2e-16`），且 `缺陷 − 参考 = [-8.067e-03, 3.237e-06, 0]` 与此前记录的残差逐位吻合。
- **修复**：把杆臂加速度装配提前为独立循环（5 行，无语义变化）。
- **连带发现**：P-07 断言此前中断整个脚本，使 P-20 从未在完整序列执行；P-20 的断言漏写转置（`1×3 − 3×1` 广播成 3×3，`norm` 取到约 11），补 `'` 后通过（差 `8.9e-16`）。组件实现本身正确。

修复后 `verify_plant_open_loop` 的 `tests_executed_count = 20`、全部 PASS。

## 4. 交付物索引

| 项目 | 位置 |
|---|---|
| Flight 修复 | `b8ae3ed`（failsafe）、`841478a`/`0851021`（着陆下探）、`b33b58e`（AUTO_LAND 模式） |
| Plant 修复（FMAT-0009） | `633eefe`（加速度装配）、`5f87578`（P-20 断言转置）、`9169cb9`/`d6f2c18`（文档） |
| Draft PR | hujunjie-hub/Flight#3（draft，未合 main）、hujunjie-hub/Flight_Matalab#1（draft） |
| Flight_Matalab | `139646f`、`a016d48`、`92eb036`、`e4b55e8`、`86c128f`、`53f2a7b`、`633eefe`、`5f87578`、`9169cb9` |
| RUN_ID | `20261110T092328651Z_9169cb9` |
| ZIP | `work/validation/archives/20261110T092328651Z_9169cb9.zip`（23 个证据文件 + `run_manifest.json`，共 24 个条目） |
| ZIP SHA-256 | `d8f90759f5ec086cf869169125f6f2b00b6277ef5181f27683c4220cbe420945` |
| 源指纹 | `857d6d6de3b39710b05aa0554d2fc13168a365782bd1e0ffce87270382b1bcd6`（早前两轮为 `7c514e63…`、`275e8374…`） |
| FMS 单元测试报告 | Flight `tests/flight_management` 主机套件输出（993 checks / 0 failures） |
| M5 单测 | Flight `tests/guidance` 主机套件（9515 checks / 0 failures） |

## 5. 复现方式

```powershell
# 同级 Flight 仓库切到 fix/fmat-0008-first-reference-race
cd E:\Flight\Flight_Matlab_Test
matlab -batch "cd(pwd); addpath('tools'); addpath('tests'); addpath(fullfile(pwd,'models','plant')); root=flight_startup; d=fullfile(root,'work','validation'); if ~isfolder(d), mkdir(d); end; diary(fullfile(d,'matlab_acceptance_diary.txt')); diary on; rep=run_component_checks; fprintf('COMPONENT_STATUS=%s\n',rep.status); diary off;" *> work\validation\matlab_batch_console.log
pwsh -File .\tools\archive_validation_run.ps1
```

上面的命令即 [验收与结果提交](../MATLAB-验收与结果提交.md) §8 的流程：打开 diary 后调用 `run_component_checks`，控制台输出另存 `work/validation/matlab_batch_console.log`，两者随归档进入 ZIP。

预期：`COMPONENT_STATUS=PARTIAL_PASS`，MIL/DataSIM/ExtINS 回放通过，组件门 13 项中 12 项 PASS、`plant` 为设计内 PARTIAL（20/20 用例通过），产出带源指纹的 ZIP。
