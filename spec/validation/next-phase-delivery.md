# 下一阶段交付清单（截至 RUN_ID `20261110T182649341Z_3b0d751`）

## 0. 新会话接管必读（2026-11-11 交接）

旧会话已推进 14 轮并到达上下文上限，按 [AGENT 操作指南](AGENT-操作指南.md) §12 交接。新会话**不要**从聊天摘要续接，按下面顺序核对。

**基线**

| 项 | 值 |
|---|---|
| Flight_Matalab | `optimize/sil-physical-parameter-alignment` @ `400eba5`（Draft PR #1） |
| Flight 上游 | `test/fmat-0012-m6-controller` @ `dfb36a7` |
| 最后归档 | `work/validation/archives/20261110T180223584Z_199e87a.zip`，SHA-256 `cfb1ab4fef23a60a78c12b370d96909ce2e5a8182cc06debe112629594ec9031`，`source_clean=true` |
| 归档自对账 | `python tools/verify_archive_claims.py` → 22/22 |

**已完成且有归档证据**：M7 Ground Stop 执行器事务（230 checks、100.5 ms ≤ 105.5 ms、`FIRMWARE_GROUND_STOP_CERTIFICATE`）、P-10b 报告口径（#17）、归档分类（#16）、`controller.c` 越界读（#15）、M6 诊断通道与逐 job 证据。

**未完成**

1. **M6 修复（P0）**——根因链条已成立：MPC 在地上时水平指令比 PD 少 0.2038 m/s²（占空 20%），把飞行器推到 0.58 m/s，越过 `ground_stable` 的 `|v_h| ≤ 0.20`（`fms_safety.c:101-104`），LANDED 不成立，TAKEOFF `reason=5`，场景无法起飞（竖直通道、导航能力、prearm、位置环指令均已排除）。**三个修复选项需要用户选择**；第 47 轮核对后修正：控制模块**没有任何 landed/ground 信号**，所以选项 1/2 实际需要扩展契约，最省的是选项 3（改 Plant 摩擦），但它推翻 P-17 既有结论。详见 FMAT-0012 §4.5.2。
2. **#13 FMS 侧两阶段 DISARM**——执行器侧已 PASS，但 FMS 仍在 `PRODUCT_CMD_DISARM`（`fms.c:599-626`）里把 `ARM_STATE_DISARMING` 立刻跳到 `DISARMED`。改动清单见 §7.4。
3. **Issue 状态更新**——本环境无 GitHub 写权限，文案见 §6。

**两条已知陷阱（会浪费一整轮）**

- 状态帧**第 75～108 列是 `FAILSAFE_TERMINAL` 的终端锁存值**，不是实时状态；land 状态不起作用时它恒为 0，别拿它做实时判据。
- `config/flight_baseline.json` 会在重建 Host SIL 时被重写；**先提交它再跑完整回归**，否则 `source_clean=false`，整轮归档只能作废重跑（已发生两次）。

**第一条命令**

```powershell
git -C E:\Flight\Flight_Matlab_Test status --short; git -C E:\Flight\Flight_Matlab_Test rev-parse HEAD
python -B tools\verify_archive_claims.py --run-id 20261110T180223584Z_199e87a
pwsh -NoProfile -File .\tools\build_flight_runtime.ps1 -GccDir 'D:\STM32CubeCLT\mingw64\bin'
```

本文件汇总本轮的实际产出、证据位置与未闭合项。所有数字均来自同一轮 `run_component_checks`，不是多轮拼接。

> **BLOCKER_STATUS: BLOCKED（2 项）**
> 1. **M6 MPC job gate 未达标**（[Issue #12](https://github.com/hujunjie-hub/Flight_Matalab/issues/12)），根因已定量，修复与既有验收场景的起飞前置条件冲突，需控制层决策。
> 2. **本环境无 GitHub 写权限**：`gh` 未安装、无 token、未认证 REST API 被限流（403）。Issue 状态变更待人工执行（待办文案见第 6 节）。
>
> M7 Ground Stop 阻塞已解除（2026-11-11，见 2.2）。

## 1. 交付物

| 项目 | 值 |
|---|---|
| RUN_ID | `20261110T180223584Z_199e87a` |
| ZIP | `work/validation/archives/20261110T180223584Z_199e87a.zip`（47 个证据文件，`m6_use_trace.json` 覆盖 4.0–10.5 s） |
| ZIP SHA-256 | `cfb1ab4fef23a60a78c12b370d96909ce2e5a8182cc06debe112629594ec9031` |
| `component_status` | **FAIL**（18 PASS、1 PARTIAL、1 FAIL；FAIL 只有 `m6_jobs`） |
| source 指纹（磁盘） | `c16f2fa05b8adce192ea96331eec9fea9e308dc15a368743a2cd9de278031c31` |
| source 指纹（committed） | `982054e602b0bece7065e44b6b55f1d4a375471c3b0c6df2397ed6a7f70d6b38` |
| artifact 指纹 | `2d995a22d16b0fa236cf20bf707cbfb5d0fa05e4bf10e7ccefcbe3a920a66c7c` |
| `source_clean` | true（Flight_Matalab `199e87a`，manifest 的 before/after commit 与之一致） |
| Flight 上游 | `cf92ed2`（分支 `test/fmat-0012-m6-controller`） |
| 生成文件分类 | `pre_existing_local_change_modified_by_run` 5、`pre_existing_local_change` 4、`commit_candidate` 1、`excluded_from_source` 13 |
| PR 状态 | Flight_Matalab#1 Draft；Flight#3 Draft；Flight#4 Draft；`main` 未改动 |
| 归档对账 | `python tools/verify_archive_claims.py --run-id 20261110T180223584Z_199e87a` → **22/22 PASS** |
| 已被取代的归档 | `…1616`/`…1701`（M6 诊断与 M7 首轮）、`20261110T165750883Z_c2b04c6`（M7 首轮，运行前文档未提交，`source_clean=false`）；全部保留不删 |

## 2. 本轮实际结果

### 2.1 M6 MPC job（P0，Issue #12）——证据补齐、根因定量、未修复

诊断通道：`middleware/model/control/mpc_diagnostics.h`（Host 构建落盘，不改变控制决策）、`mpc_jobs.json`（逐 job）、`m6_runtime_stats.json.consumer`（逐 1 kHz 消费点）。

| 要求 | 实测 |
|---|---|
| job / solved / rejected | 488 / 20 / 468 |
| 成功率 / 时间加权覆盖率 | 4.10% / 1.54%（门槛 99% / 90%） |
| 首个拒绝阶段分布 | `RESIDUAL` 468，`OK` 20；`DOMAIN`/`REFERENCE`/`BOUNDS`/`SOLVER_CALL`/`SOLVER_STATUS`/`NON_FINITE`/`PRIMAL`/`THRUST`/`DEADLINE` 全 0 |
| solver status | 488 个 job 全部 `CONTROL_SOLVER_SOLVED` |
| primal residual | min 4.7e-9，median 3.0e-8，max 1.35e-3 |
| dual residual | min 1.31e-4，p25 1.37e-3，**median 1.75e-3**，p75 3.51e-3，max 1.00e-2 |
| 独立约束违反量 / 推力超出 | max 8.6e-4（p75 及以下为 0）/ 全 0 |
| 消费点 | 9760 个，`used` 80（0.82%），`backup_expired` 9680，其余备份条件全 0 |
| 覆盖率口径 | 门限分母保持**整轮**（不变）：400,000 µs / 26 s = **1.538%**；另报告"轨迹模式可用窗口" 751 tick = 15.02 s 下的 **2.663%**（仅供诊断，不参与判定）。即使取最有利分母仍远低于 90%，**缺口不是分母口径造成的** |
| 快照寿命 | `expires-sample` max 8000 µs；`expires-eval` max 5000 µs；`eval-sample` 恒 3000 µs |

机制（已定量，见 [FMAT-0012 附记](FMAT-0012-mpc-consumer-path.md) §4.5）：

1. 拒绝**只**来自应用侧对 dual residual 的**绝对** 1e-3 门限；OSQP 工作区 `eps_abs=eps_rel=1e-3`，其停止准则为 `1e-3 + 1e-3·max(‖Px‖,‖A'y‖,‖q‖)`≈2e-3，median 1.75e-3 正好落在求解器合同内。
2. 只改求解器终止准则（`eps_rel=0`，门限不动）后 solved 升到 **489/489**、被采用 1956/9780，但 MIL 最大高度从 2.098 m 掉到 **0.242 m**，且 6.0 s 的 TAKEOFF 被拒（`ack=0, reason=5` = `land != LANDED`）。**因果机制两轮内被两次否证**：(a) 1 kHz 轨迹显示地面窗口 MPC 占空比仅 17.1%、有效平均 1.47e-3 m/s²，1.8 s 只值 2.4 mm → "地面段抬升 242 mm"不成立；(b) 高度/推力时程显示 6.0 s 时**仍在地面**（3.7 mm），失败形状是**爬升率掉一个量级**（8.0 s：基线 1.2887 m vs 0.1176 m），而推力反而略高（14.704 N vs 14.197 N）。机制未定位；第 41 轮把窗口扩到 10.5 s 后又排除了**位置环加速度指令**：爬升段 MPC 的 z 指令比 PD 更向上（−0.06…−0.16 m/s²、占空比 20%），若它起作用只会让爬升更快。**修复入口不在 MPC 的数学里**。第 42 轮已把剩下的通路缩小到 land 判定：`fms.c:648` 的 `reason=5` 来自 `land.state != LANDED`，而 LANDED 由 `fms_safety.c:101-104` 的四条件决定（`|v_h| ≤ 0.20 m/s`、`|vz| ≤ 0.15 m/s`、`|a_z| ≤ 0.50 m/s²`、能力掩码齐全）并需保持 2 s。`control_level` 全仓库无读取点，已排除。第 43 轮已完成不需要改固件的那部分：地面窗口水平速度 基线 **0.0029 m/s** vs `eps_rel=0` **0.5802 m/s**（t=5.237 s 越过 0.20 门限），且 MPC 水平指令比 PD 平均少 **0.2038 m/s²**（占空 20%）。**失败与竖直通道无关，与地面段水平速度不平衡有关**；唯一未实测的环节是 `land.state` 是否真的因此退回 UNKNOWN（状态帧第 78 列不是实时 land 状态）。**二义性已分流**：状态帧显示两种构建在 6.0 s 前后导航能力掩码均为 **0xFF**（POS_HOLD 只需 0x78）、prearm READY、failed 0x00，因此 `fms_capable_for_mode` 不是失败原因，`reason=5` 来自 **land 状态分支**。链条四环中三环已实测（水平指令差 −0.2038 m/s²、地面滑移 0.58 m/s 越过 0.20 门限、能力分支排除），仅"`land.state` 何时退回"不可观测（状态帧第 78 列是 `FAILSAFE_TERMINAL` 的终端锁存值，按规范恒为 0，不是实时 land 状态——已更正，见附记）。**修复方向已可确定：地面段水平速度不平衡导致 LANDED 不成立**；三个修复选项均属控制层决策，需你选择。
3. MPC 与 PD 的逐轴差值上限只有 0.33 m/s²（x）、0.33（y）、0.16（z），因此失败是**起飞前置条件耦合**，不是控制量幅值回归。

该实验已整条回退；`eps_rel` 恢复 1e-3，MIL 回到 2.098 m / TAKEOFF ack=1。**没有放宽容差、没有跳过候选验证、没有延长旧解有效期。**

### 2.2 M7 Ground Stop（P0，Issue #13）——已实现

真实固件路径 `middleware/actuator/output_guard/actuator_guard.c`，本轮新增 `GroundStopCertificate` 契约与事务：

| 要求 | 实测（Flight M7 主机套件，230 checks / 0 failures） |
|---|---|
| GroundStopCertificate | `MSG_GROUND_STOP_CERTIFICATE`(56)；stop code 只接受 0，速率只接受 `(0, 100]` N/s，生命周期只接受 LANDED/DISARMING（取值 0x1001/0x1002，避免与 `LandedState` 混淆） |
| LANDED / DISARMING 生命周期限制 | 畸形证书 5 类全部拒绝（`M7-11`） |
| 撤销后仍可停止 | PASS（`M7-12`：先撤销 Permit 再受理证书） |
| 最大 100 N/s 降推力 | PASS（`M7-13`：单帧最大 0.25 N，推力单调不回升） |
| stop code 0 | 仅此码通过，其余 `STATUS_OUT_OF_RANGE` |
| ZERO_TARGET_APPLIED 回执 | PASS（`M7-14`：四路恰好 0 N 时写入 `ACTUATOR_RECEIPT_ZERO_TARGET_APPLIED`） |
| 最坏应用时间 ≤105.5 ms | PASS（`M7-15`：**40 帧 / 100,000 µs 归零，受理到应用 100,500 µs**；超预算的速率在受理时即被拒绝，而不是稍后超时） |
| 确认零目标后才 DISARMED | PASS（`M7-16`：仅在零回执那一帧进入 DISARMED 并 inhibit） |
| DISARMED 后禁止非零输出 | PASS（`M7-16`：之后的 demand 与帧边界均不产生提交，输出保持零推力码；latch 直到下次 `actuator_init()`） |

`actuation_report.json` 相应字段：`ground_stop_transaction=PASS`、`ground_stop_evidence=FIRMWARE_GROUND_STOP_CERTIFICATE`、`ground_stop_max_apply_us=105500`、`ground_stop_max_ramp_nps=100`。未覆盖：FMS 侧签发触发逻辑、真实 ESC 物理推力响应、PIL/HIL。

### 2.3 P-10b（P1，Issue #14 / #17）——报告口径修复、数字对账完成

| 项目 | 本轮实测（同一 RUN_ID） |
|---|---|
| PPS 事件 / 拒绝 | 21 / 1（该 1 次为刻意 4 s 失锁后的首个无效边沿） |
| RECTIMEA 帧 / GNSS 观测 | 21 / 21 |
| `utc_valid` / `utc_mapping_epoch` / `accepted_intervals` | 1 / 11 / 12 |
| UTC 不确定度 | 384,042 ns |
| 失锁期 `utc_valid` / holdover / 不确定度 | 0 / 4.5 s / 225,359,042 ns |
| 恢复后 `utc_valid` / 不确定度 | 1 / 384,042 ns |
| 顶层 `p10b_report.json` | `utc_mapping_verified=PASS`、`holdover_recovery_verified=PASS`、`gates_consistent=true`、`overall_P10_status=PARTIAL` |

对 #17 的处置：旧文档的 26/0/26、epoch 13、25 intervals **是错的**；`9131a72` 归档的原始报告一直是 21/1/21/21、epoch 11、12 intervals。本轮已把交付文档改成归档数字，并修掉制造矛盾的报告缺陷：

- 注入门不再写顶层 `p10b_report.json`，也不再硬编码 `NOT_RUN`（改由 `verify_p10b_summary` 用本轮三份报告合成）；
- 失锁门不再把派生判定写进 `loss_utc_valid`，测量值与判定分开（`utc_lost_verified`）。

P-10 整体仍为 `PARTIAL`：物理 TIM2 capture ISR、UM982 UART/DMA、`sensor_gnss_poll` 端到端与板级时钟不在本轮证据内。

### 2.4 归档证据分类（P1，Issue #16）——修复

`tools/fingerprint_artifacts.py` 现在按运行前后 artifact 摘要区分"运行前已脏"的两种情形，新增 `pre_existing_local_change_modified_by_run`。本轮真实工作区的分类结果证明缺陷已消除：5 个文件被本轮改写（原先全部被归为"用户既存修改"）、4 个未被触碰。自测 A-01…A-08 全 PASS（新增 A-07/A-08）。未删除或覆盖任何用户模型、字典、录制文件。

### 2.5 固件缺陷（P2，Issue #15）——修复

`controller.c` 原 `finite_array(n->core.position_ned_m, 6)` 对 3 元素数组越界读。意图由同一判据的需求掩码可确认（同时要求水平/垂直位置与速度有效），已拆成对 `position_ned_m` 与 `velocity_ned_mps` 各 3 个元素的显式检查。Flight M6 主机套件仍为 13 + 11 checks、0 failures。

## 3. 实际执行的测试

| 套件 | 结果 |
|---|---|
| Flight `tests/control`（M6 组装 + 上下文守卫） | 13 + 11 checks / 0 failures |
| Flight `tests/actuation`（M7，经组件门） | 38 checks / 0 failures |
| Flight `tests/simulation` SIL 场景（构建时） | 4147 checks / 0 failures |
| Matalab 归档可靠性 A-01…A-08 | 8/8 PASS |
| Matalab 完整入口 `run_component_checks` | 18 PASS / 1 PARTIAL / 1 FAIL（FAIL 仅 `m6_jobs`） |
| 26 s MIL 闭环 | 最高 2.0982 m、终速 0.0151 m/s、MPC worker 1300 次、执行器提交 8296 次 |
| 快速 MIL 复跑（`work/m6probe.m`） | 3 次确定性一致（2.098 m） |

## 4. 修改文件清单

**Flight**（`test/fmat-0012-m6-controller`，`a40c4b2`）

- `middleware/model/control/mpc_diagnostics.h`（新增）——`MpcRunStats`、`MpcJobRecord`、`MpcConsumerStats` 与接口
- `middleware/model/control/outer_loop/quad_x4/mpc_solver/mpc.c`——每 job 首个拒绝阶段与残差/时间戳记录
- `middleware/model/control/outer_loop/quad_x4/position_tracking/position_control.c`——逐条件消费计数、寿命直方图、MPC−PD 差值
- `middleware/model/control/inner_loop/quad_x4/attitude_rate_control/controller.c`——`mpc_consumer_reset()` 调用点、#15 越界读修复
- `middleware/model/control/inner_loop/quad_x4/attitude_rate_control/controller_internal.h`——移除重复定义

**Flight_Matalab**（`optimize/sil-physical-parameter-alignment`，`a5628f7`）

- `adapters/flight_runtime/fmt_flight_runtime.c`——包含固件头文件（不再自带结构体副本）、`m6_jobs.json`
- `tests/verify_m6_jobs.m`——阶段计数 + 分位数证据；`tests/verify_flight_entries.m`——`m6_jobs_mil.json` 快照
- `tests/verify_p10b_pps_rectime.m`、`tests/verify_p10b_holdover.m`、`tests/verify_p10b_summary.m`（新增）、`tools/run_component_checks.m`
- `tools/fingerprint_artifacts.py`、`tests/verify_archive_reliability.m`
- `config/flight_baseline.json`、`spec/validation/FMAT-0012-mpc-consumer-path.md`、`spec/validation/archive-evidence-model.md`、`spec/MATLAB-验收与结果提交.md`、本文件

## 5. Issue 状态

| Issue | 本轮动作 | 建议状态 |
|---|---|---|
| #12 M6 成功率/覆盖率 | 证据补齐、根因定量、实验回退 | `IN_PROGRESS` + `BLOCKER_IN_PROGRESS` |
| #13 M7 Ground Stop | 已实现并实测 | `FIXED_WAITING_RETEST` |
| #14 P-10b 完整集成 | 报告口径修复、证据对账 | `IN_PROGRESS`（P-10 仍 `PARTIAL`） |
| #16 归档分类 | 已修复并自测 | `FIXED_WAITING_RETEST` → 待用户回归后 `VERIFIED` |
| #17 文档/归档数字 | 已对账并修复报告缺陷 | `FIXED_WAITING_RETEST` |
| #15 controller.c 越界 | 已修复 | `FIXED_WAITING_RETEST` |

## 6. 待人工执行的 Issue 更新（本环境无法写 GitHub）

**#16**：状态 `IN_PROGRESS → FIXED_WAITING_RETEST`。修复 commit `0a4a19e`；证据 RUN_ID `20261110T163238005Z_a5628f7`（ZIP SHA-256 `307279fc…`）。`generated_assets.json` 现区分 `pre_existing_local_change_modified_by_run`(5) 与 `pre_existing_local_change`(4)；A-07/A-08 覆盖两种情形，A-01…A-08 全 PASS。根因：`disposition_for()` 在 `code && dirty_before` 分支直接返回旧类别，未比较运行前后摘要。

**#17**：状态 `IN_PROGRESS → FIXED_WAITING_RETEST`。修复 commit `57087e0`；同一 RUN_ID。事实：`9131a72` 归档原始值为 21/1/21/21、epoch 11、12 intervals、失锁期 `utc_valid=0`；旧文档的 26/0/26/epoch13/25 为错误数字。另修复两处报告缺陷：注入门硬编码 `NOT_RUN`、失锁门把派生判定写入 `loss_utc_valid`。

**#15**：状态 `OPEN → FIXED_WAITING_RETEST`。修复 commit 见 Flight `a40c4b2`；M6 主机套件 13+11/0 failures。

**#13**：执行器侧 `IN_PROGRESS → FIXED_WAITING_RETEST`（**不得关闭**）。修复 commit 见 Flight `80bca5e`；实测 Flight M7 主机套件 230 checks / 0 failures，`ground_stop_transaction=PASS`、`ground_stop_evidence=FIRMWARE_GROUND_STOP_CERTIFICATE`，40 帧 / 100,000 µs 归零、受理到应用 100,500 µs ≤ 105,500 µs；DISARMED 仅在 `ZERO_TARGET_APPLIED` 后进入且后续无输出。**遗留（阻塞端到端关闭）**：FMS 侧签发 `GroundStopCertificate` 的触发逻辑尚未实现，物理 ESC 推力响应与 PIL/HIL 未验证——执行器侧 PASS 不等于停止功能端到端完成。

**#12**：保持 `IN_PROGRESS`，追加本轮证据：拒绝阶段分布（`RESIDUAL` 468 / `OK` 20）、dual residual 分位数（median 1.75e-3）、以及"`eps_rel=0` 后 489/489 但 TAKEOFF `reason=5`"的因果链。

## 7. 下一阶段任务（按依赖顺序）

1. **M6 先做判别测量，再谈地面段策略（P0，阻断 #12）**：第 2.1 节的量级检查说明"MPC 零偏抬升 0.24 m"目前只是候选假设（20% 占空比只解释 0.052 m）。**该测量已在第 39 轮完成并否证了地面段偏置假设**（见 §2.1 第 2 条）。下一项判别测量改为：把两种构建的 `ControlHealth`、`m6.solver_failures`、FMS `land.state`、`prearm` 逐 tick 对比，确认"接受解改变健康/状态上报"是否是真正的通路。**地面段策略的用户决策不再是下一步**——在健康通路核实前，控制层策略无需裁定。
2. **M6 快照到期链（P0）**：把 `actuator_capability/status` 的 5 ms 消息 TTL 从计划有效期里移除。计划不消费执行器遥测（两项都不进 QP），5 ms 是消息新鲜度契约；`eps_rel` 修复之前的实验已证明在既有场景下无害。第 1 项完成前不得单独启用。
3. **M6 门限与求解器一致性（P0）**：1e-3 门限保留，OSQP 改为绝对终止（`eps_rel=0` 或重新生成工作区）。与前两项一起启用并重新验收。
4. **M7 Ground Stop（执行器侧已完成，FMS 侧待接）**：执行器侧事务与回执已完成（第 2.2 节）。本轮把余项的调查结论固化为事实，避免下一轮重新摸索：

   - **两阶段的位置不是 `fms_permit_ground_disarm()`**。那个函数只服务"首次参考超时且已 LANDED"路径，此时从未获得控制权、没有需要斜坡下降的推力；把它改成两阶段会改写 `test_first_reference_window_expires_to_ground_stop` 的既有断言（同步 DISARMED + REVOKED），理由不成立。
   - **真正的调用点是 `fms.c` 的 `PRODUCT_CMD_DISARM` 分支**：它先把 `arm_state` 置为 `ARM_STATE_DISARMING`（枚举里已存在该中间态），随后在同一个 handler 里立刻置 `ARM_STATE_DISARMED`。要做的就是把"立刻"改成"等零回执或超时回退"。
   - 安全属性：该分支已先 `fms_permit_revoke`，因此即使证书链路完全不通，执行器也会因无有效 Permit 进入 inhibit；加上 105.5 ms 的有界回退，两阶段不会把飞行器留在有推力的中间态。
   - 待改文件（已定位）：`fms_internal.h` 的 `FmsPermit`（新增 pending/requested_us）与 `FmsInputs`（新增 `const ActuatorCommitReceipt *receipt`）；`fms_contract.h` 的 `FmsOutputView`（新增 `GroundStopCertificate ground_stop`）；`actuation_permit.c` 的 `fms_ground_stop_fill()`；`fms.c` 的 DISARM 分支与 tick 完成条件；`applications/tasks/mission/task_mission.c`（把 `fms_output.ground_stop` 紧挨着 `actuator_update_permit` 调用 `actuator_guard_ground_stop()`，并把 `plan_bundle.receipt` 送进 `FmsInputs`）。不需要改 `ControlBundle` 或 `task_actuator.c`，因为 Mission 已经直接更新执行器许可。
   - **验证手段**：FMS 主机套件可在本机 WSL 中直接运行（`bash -lc "cd /mnt/e/Flight/Flight && bash tests/flight_management/run_host_tests.sh"`），改前基线 **993 checks / 0 failures**。改后必须重跑该套件与完整 MATLAB 回归。

5. **P-10b（P1，Issue #14）**：真实 UART/DMA、PPS capture、`sensor_gnss_poll` 端到端；区分 Host 注入证据与物理 TIM2/板级证据。
6. **覆盖率口径（P2，已量化待裁定）**：`m6_report.json` 现已同时给出两个分母（整轮 1.538% / 轨迹模式可用窗口 2.663%），判定仍用整轮口径不变。**需要 Issue #12 明确哪个分母是合同口径**——这是验收标准变更，Agent 不得自行切换；数据已证明无论取哪个都远低于 90%。

## 8. 边界声明

- 本轮全部结果来自 PC MATLAB/Simulink（R2026b Update 1）+ Windows Host SIL，**不构成 H723 实机、PIL/HIL 或实飞验证**；
- 未实测项一律保持 `NOT_RUN`，没有以"应该可以"替代证据；
- `eps_rel=0` 实验与第 37 轮两次实验均已回退，未作为改进计入结果；
- 未放宽任何验收门限，未跳过候选解验证，未延长旧解有效期，未修改 `main`，未合并任何 PR。
