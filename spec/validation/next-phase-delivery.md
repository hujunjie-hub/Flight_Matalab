# 下一阶段交付清单（截至 RUN_ID `20261110T170102013Z_c2b04c6`）

本文件汇总本轮的实际产出、证据位置与未闭合项。所有数字均来自同一轮 `run_component_checks`，不是多轮拼接。

> **BLOCKER_STATUS: BLOCKED（2 项）**
> 1. **M6 MPC job gate 未达标**（[Issue #12](https://github.com/hujunjie-hub/Flight_Matalab/issues/12)），根因已定量，修复与既有验收场景的起飞前置条件冲突，需控制层决策。
> 2. **本环境无 GitHub 写权限**：`gh` 未安装、无 token、未认证 REST API 被限流（403）。Issue 状态变更待人工执行（待办文案见第 6 节）。
>
> M7 Ground Stop 阻塞已解除（2026-11-11，见 2.2）。

## 1. 交付物

| 项目 | 值 |
|---|---|
| RUN_ID | `20261110T170102013Z_c2b04c6` |
| ZIP | `work/validation/archives/20261110T170102013Z_c2b04c6.zip`（46 个证据文件） |
| ZIP SHA-256 | `f53aa6a1001b40b2e92efabab37fc0e8f49e3742b57447a07b3a4b1f8a239c5b` |
| `component_status` | **FAIL**（18 PASS、1 PARTIAL、1 FAIL；FAIL 只有 `m6_jobs`） |
| source 指纹（磁盘） | `68fc81d080685d4bf66ae89b799a9891ff6b89976b5f137290a493b1bb7c8631` |
| source 指纹（committed） | `5e1bfd45ee4d2f0b46d0e0e32a6cfb9f3cf92645d5a650694ecbb5af3a22edc0` |
| artifact 指纹 | `ad3f90db2a04b2d2b304b02b13a84359c8130ed6dd8ee4c7b2054cc904a0802a` |
| `source_clean` | true（Flight_Matalab `c2b04c6`，manifest 的 before/after commit 与之一致） |
| Flight 上游 | `80bca5e`（分支 `test/fmat-0012-m6-controller`） |
| 生成文件分类 | `pre_existing_local_change_modified_by_run` 5、`pre_existing_local_change` 4、`commit_candidate` 1、`excluded_from_source` 13 |
| PR 状态 | Flight_Matalab#1 Draft；Flight#3 Draft；Flight#4 Draft；`main` 未改动 |
| 已被取代的归档 | `20261110T162048653Z_61a90f6`（M6 诊断首轮）、`20261110T165750883Z_c2b04c6`（M7 首轮，运行前文档未提交，`source_clean=false`）；两者均保留不删 |

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
| 快照寿命 | `expires-sample` max 8000 µs；`expires-eval` max 5000 µs；`eval-sample` 恒 3000 µs |

机制（已定量，见 [FMAT-0012 附记](FMAT-0012-mpc-consumer-path.md) §4.5）：

1. 拒绝**只**来自应用侧对 dual residual 的**绝对** 1e-3 门限；OSQP 工作区 `eps_abs=eps_rel=1e-3`，其停止准则为 `1e-3 + 1e-3·max(‖Px‖,‖A'y‖,‖q‖)`≈2e-3，median 1.75e-3 正好落在求解器合同内。
2. 只改求解器终止准则（`eps_rel=0`，门限不动）后 solved 升到 **489/489**、被采用 1956/9780，但 MIL 最大高度从 2.098 m 掉到 **0.242 m**：地面段 MPC 零偏使飞行器提前离地，LandDetector 失去 `LANDED`，6.0 s 的 TAKEOFF 以 `reason=5` 被拒且不重发。
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

1. **M6 地面段与空中段分离（P0，阻断 #12）**：在 `LANDED` 期间不得让 MPC 快照改变离地判定（例如地面段不采用快照，或采用但把净加速度限幅到不产生升力）。第 2.1 节已证明：不解决这一项，任何提高接受率的修复都会以 `reason=5` 失败。这是需要控制层确认的设计决策，**需要用户决策**。
2. **M6 快照到期链（P0）**：把 `actuator_capability/status` 的 5 ms 消息 TTL 从计划有效期里移除。计划不消费执行器遥测（两项都不进 QP），5 ms 是消息新鲜度契约；`eps_rel` 修复之前的实验已证明在既有场景下无害。第 1 项完成前不得单独启用。
3. **M6 门限与求解器一致性（P0）**：1e-3 门限保留，OSQP 改为绝对终止（`eps_rel=0` 或重新生成工作区）。与前两项一起启用并重新验收。
4. **M7 Ground Stop（已完成，遗留项）**：执行器侧事务与回执已完成（第 2.2 节）。剩余：FMS 侧签发证书的触发逻辑（何时在 LANDED/DISARMING 下签发、与 LandDetector/Mission 的时序约束）尚未实现，属 Issue #13 的后续范围，不得把执行器侧 PASS 当作端到端停止功能完成。
5. **P-10b（P1，Issue #14）**：真实 UART/DMA、PPS capture、`sensor_gnss_poll` 端到端；区分 Host 注入证据与物理 TIM2/板级证据。
6. **覆盖率口径（P2）**：`time_weighted_coverage` 分母是否排除非轨迹模式时段，需按 Issue #12 口径确认。

## 8. 边界声明

- 本轮全部结果来自 PC MATLAB/Simulink（R2026b Update 1）+ Windows Host SIL，**不构成 H723 实机、PIL/HIL 或实飞验证**；
- 未实测项一律保持 `NOT_RUN`，没有以"应该可以"替代证据；
- `eps_rel=0` 实验与第 37 轮两次实验均已回退，未作为改进计入结果；
- 未放宽任何验收门限，未跳过候选解验证，未延长旧解有效期，未修改 `main`，未合并任何 PR。
