# 下一阶段交付清单（截至 RUN_ID `20261110T235206650Z_78912e8`）

## 0. 新会话接管必读（2026-11-11 交接）

本轮是**新会话**（按 [AGENT 操作指南](AGENT-操作指南.md) §12 接管）的第一次交付。旧会话的交接块已由本轮替换；新会话**不要**从聊天摘要续接，按下面顺序核对。

**基线**

| 项 | 值 |
|---|---|
| Flight_Matalab | `optimize/sil-physical-parameter-alignment` @ `78912e8`（Draft PR #1，head 与 origin 一致） |
| Flight 上游 | `test/fmat-0012-m6-controller` @ `b2f33ee`（本轮新增；执行器 M7 侧仍是 `80bca5e`/`bef9022`） |
| 最后归档 | `work/validation/archives/20261110T235206650Z_78912e8.zip`，SHA-256 `07575f020d77431f49a60360cffc9823059a029358a354a01f2838558ad704c1`，`source_clean=true`，47 个证据文件 |
| 归档自对账 | `python tools/verify_archive_claims.py --run-id 20261110T235206650Z_78912e8` → **22/22 PASS** |
| 被取代的归档 | `20261110T234422185Z_78912e8`（同一次运行，但归档时 HEAD 已被文档提交推进，manifest commit 与 pre-run 快照不符，`21/22`）；保留不删，**不得**作为验收证据引用 |

**本轮已完成且有归档证据**

1. **M6（#12）修复并实测**：488/488 job 全部通过，控制路径覆盖 95.0%（详见 §2.1）。
2. **M6 地面段机制更正**：旧结论"MPC 水平指令比 PD 少 0.20 m/s² 把飞行器推走"被实测否证；真实激励是 5 ms 计划寿命造成的 MPC/PD 1 kHz 交替（详见 [附记 §4.6](FMAT-0012-mpc-consumer-path.md)）。
3. **归档/证据完整性（#16、#17）**：A-01…A-08 全 PASS，本轮 `generated_assets_summary` 正确区分 `pre_existing_local_change_modified_by_run`(5) / `pre_existing_local_change`(4) / `commit_candidate`(1) / `excluded_from_source`(13)。
4. **#15**：`controller.c` 越界读修复仍在，Flight M6 主机套件 13+11 checks / 0 failures。

**未完成（两条都需要用户裁定）**

1. **覆盖率口径（P0，阻断 #12 结案）**：验收计划写的是"时间加权覆盖率 = 有效 MPC 周期 / **闭环时长** ≥90%"，实现却用了**整轮 26 s** 做分母。实测 `worker_ticks=1300`，其中 `blocked_mode=549` 根本不进入 `mpc_solve()`，因此该分母的上限是 `751×20 ms / 26 s = 57.8%`——**任何实现都不可能达标**。三种口径的实测值见 §2.1，需要你在三者中确认合同口径（推荐：1 kHz 消费点口径，本轮 95.0%）。
2. **M7 FMS 侧两阶段 DISARM（P0，#13）**：执行器侧事务已 PASS，但 `fms.c:599-626` 仍在同一个 handler 里把 `ARM_STATE_DISARMING` 立刻置成 `ARM_STATE_DISARMED`。需要的改动跨 A 侧公共契约（`GroundStopCertificate` 已存在，但 FMS 需要 receipt 反馈与延迟 ACK 语义），属 S1 契约/安全语义决策，本轮**未动**（详见 §2.2 与 §7.2）。

**两条已知陷阱（会浪费一整轮）**

- 状态帧**第 75～108 列是 `FAILSAFE_TERMINAL` 的终端锁存值**，不是实时 land 状态；不要用它判断 landed。
- `config/flight_baseline.json` 会被重建 Host SIL 改写：**先在 `../Flight` 提交源码，再重建、提交该文件，最后才跑完整回归**，否则 `source_clean=false`（本轮已按此顺序执行）。另注意 Flight 仓库 `core.autocrlf=true` 且无 `.gitattributes`：`git checkout` 会把 LF 改成 CRLF 并改变锁文件哈希，恢复生成文件请用 `git checkout <rev> -- <path>` 后核对 `external_dependencies.lock.json` 中的期望哈希。

**第一条命令**

```powershell
git -C E:\Flight\Flight_Matlab_Test status --short; git -C E:\Flight\Flight_Matlab_Test rev-parse HEAD
git -C E:\Flight status --short; git -C E:\Flight rev-parse HEAD
python -B tools\verify_archive_claims.py --run-id 20261110T235206650Z_78912e8
pwsh -NoProfile -File .\tools\build_flight_runtime.ps1 -GccDir 'D:\STM32CubeCLT\mingw64\bin'
```

> **BLOCKER_STATUS: BLOCKED（3 项）**
> 1. **覆盖率合同口径未定**（[Issue #12](https://github.com/hujunjie-hub/Flight_Matalab/issues/12)）：现有分母在数学上不可达 90%，需用户裁定；裁定前 `verify_m6_jobs.m` 判定口径不动，`component_checks.status` 只能是 FAIL。
> 2. **M7 FMS 两阶段 DISARM 需要契约/ACK 语义决策**（[Issue #13](https://github.com/hujunjie-hub/Flight_Matalab/issues/13)）。
> 3. **本环境无 GitHub 写权限**：`gh` 未安装、无 token；未认证 REST 只读可用（GET 200），写操作不可用。Issue 状态变更待人工执行（文案见 §6）。

## 1. 交付物

| 项目 | 值 |
|---|---|
| RUN_ID | `20261110T235206650Z_78912e8` |
| ZIP | `work/validation/archives/20261110T235206650Z_78912e8.zip`（47 个证据文件） |
| ZIP SHA-256 | `07575f020d77431f49a60360cffc9823059a029358a354a01f2838558ad704c1` |
| `component_status` | **FAIL**（19 PASS、1 PARTIAL；FAIL 只有 `m6_jobs`，且只差覆盖率分母） |
| source 指纹（磁盘） | `c817e5a21e00df36dbbe14422de62e8b2ff8276b1c30c65233ecff7d3c5a0155` |
| source 指纹（committed） | `cb643f8e34a9cd3e0d549abd8d7cb35cc3a559e62d4744a92f393bcf82b2c558` |
| artifact 指纹 | `ad7a51a8f802a1dd254a9504374e9b8165ea6ad5f12d4182f8c2e63813f90840` |
| `source_clean` | true（Flight_Matalab `78912e8`，Flight `b2f33ee`） |
| 生成文件分类 | `pre_existing_local_change_modified_by_run` 5、`pre_existing_local_change` 4、`commit_candidate` 1、`excluded_from_source` 13 |
| PR 状态 | Flight_Matalab#1 Draft；Flight#3 Draft；Flight#4 Draft；`main` 未改动 |
| 重复性 | 同一 commit 连跑两次完整入口，`m6_report` 数字逐位一致（488/488、0.3754），MIL 最高 2.0841 m 一致 |

## 2. 本轮实际结果

### 2.1 M6 MPC（P0，#12）——修复完成，只剩覆盖率口径

**修复（Flight `b2f33ee`，`mpc.c` 两处）**

1. **计划有效期不再被 5 ms 执行器消息 TTL 掐住**：`actuator_capability/status` 的 `valid_until_us` 从到期取 min 链中移除。两者都不进入 QP，5 ms 是遥测新鲜度契约，不是计划有效期；此前它把计划压到 20 ms 周期的四分之一。
2. **求解器改绝对终止**：`mpc_reset()` 用 `osqp_update_settings()` 把工作区 `eps_rel` 置 0（`eps_abs` 仍 1e-3），使 OSQP 满足应用侧**未改动**的绝对 1e-3 双残差门限。生成的工作区与 `UPSTREAM_LOCK.json` 保持逐字节一致，依赖锁未变。

**实测（同一 RUN_ID）**

| 要求 | 基线（上一轮） | 本轮 |
|---|---|---|
| job / solved / rejected | 488 / 20 / 468 | **488 / 488 / 0** |
| 成功率 | 4.10% | **100%（门槛 99%）** |
| 首个拒绝阶段 | `RESIDUAL` 468 | 全部 `OK`，其余阶段全 0 |
| dual residual | median 1.75e-3 | min 3.20e-4 / median 8.32e-4 / **max 9.995e-4** |
| primal residual | max 1.35e-3 | max 7.08e-4 |
| 快照寿命（expires−sample） | 8,000 µs | **23,000 µs** |
| 消费点 used / samples | 80 / 9760（0.8%） | **9272 / 9760（95.0%）** |
| 其余回退条件 | 全部为 0 | 全部为 0（`backup_expired` 488 = 每 job 1 tick） |
| 求解超时 / 精度不足 / 不可行 | 0 | 0 |
| 26 s MIL | 2.0982 m，TAKEOFF ack=1 | **2.0841 m，TAKEOFF/ARM/LAND/DISARM 全部 ack=1**，终速 0.0249 m/s，三入口回放一致 |

**覆盖率口径（需裁定）**

| 口径 | 本轮值 | 结构上限 | 备注 |
|---|---|---|---|
| 整轮 26 s（**当前判定口径**） | 37.54% | **57.77%** | `blocked_mode=549`，751 个可尝试 tick；任何实现都到不了 90% |
| worker 可用窗口 15.02 s | 64.98% | 100% | 仍受 `blocked_validation=263` 影响 |
| 1 kHz 消费点 `used/samples` | **95.00%** | 100% | 直接测量"控制路径上 MPC 接管了多少时间"，PD 回退计入分母 |

`fallback_counted_as_uncovered` 在三种口径下都成立，因此切到消费点口径不是放宽门限，而是把分母改回"闭环时长"的原意。**这是验收标准变更，Agent 未执行。**

**地面段机制更正（详见[附记 §4.6](FMAT-0012-mpc-consumer-path.md)）**

旧结论（"MPC 水平指令比 PD 少 0.2038 m/s²，把飞行器推到 0.58 m/s"）被三个构建的实测否证：滑移方向上位置环在**刹车**（5.4 s 时 PD +1.026、MPC +0.799 m/s²，而飞行器沿 −x 漂移）；水平加速度 100% 由倾斜推力解释（最大残差 0.040 m/s²）；地面俯仰与指令**反向**（指令 −0.6…−11.0°，实测 +5.35°）。真实激励是 8 ms 计划寿命造成的 MPC/PD 每 20 ms 数次切换；寿命修好后占空比 0.8%→95%，俯仰落在 −0.46…0°，地面 `|v_h|` 0.58→0.046 m/s。

### 2.2 M7 Ground Stop（P0，#13）——执行器侧保持 PASS，FMS 侧未动

| 项目 | 本轮实测（同一 RUN_ID） |
|---|---|
| `ground_stop_transaction` | PASS（`FIRMWARE_GROUND_STOP_CERTIFICATE`） |
| 最坏应用时间 | 100,500 µs ≤ 105,500 µs（40 帧 / 100,000 µs 归零） |
| 最大降推力速率 | 100 N/s |
| 零回执后才 DISARMED | PASS；DISARMED 后无非零输出 |
| Flight M7 主机套件 | 230 checks / 0 failures |

未完成：`fms.c:599-626` 的 `PRODUCT_CMD_DISARM` 仍在同一 handler 内 `DISARMING → DISARMED`。改动会跨 A 侧公共契约与 ACK 语义（要么给 `FmsOutputView` 加证书并把 `ActuatorCommitReceipt` 送进 FMS，要么只做"定时等待 + Mission 侧合成证书"的弱化版），需要你先定方向，见 §7.2。

### 2.3 P-10b（P1，#14）——报告一致，端到端仍 PARTIAL

| 项目 | 本轮实测 |
|---|---|
| PPS 事件 / 拒绝 | 21 / 1（刻意 4 s 失锁后的首个无效边沿） |
| RECTIMEA 帧 / GNSS 观测 | 21 / 21 |
| `utc_valid` / `utc_mapping_epoch` / `accepted_intervals` | 1 / 11 / 12 |
| UTC 不确定度 | 384,042 ns |
| 失锁期 `utc_valid` / holdover / 不确定度 | 0 / 4.5 s / 225,359,042 ns |
| 顶层 `p10b_report.json` | `gates_consistent=true`、`overall_P10_status=PARTIAL` |

`not_validated` 仍为：物理 TIM2 capture ISR、UM982 UART/DMA 投递、`sensor_gnss_poll` 端到端、板级时钟。本轮**没有**新增 P-10b 代码；Host 注入与真实硬件证据的分界已写进每份报告。

### 2.4 归档证据完整性（#16、#17）——验证通过

- `archive_reliability_report.json`：A-01…A-08 **8/8 PASS**（含 A-07 "运行前已脏且被本轮改写"、A-08 "运行前已脏且未被触碰"）。
- `verify_archive_claims.py --run-id 20261110T235206650Z_78912e8` → **22/22 PASS**。
- P-10b 文档数字与原始 ZIP 数字一致（21/1/21/21、epoch 11、12 intervals）。

### 2.5 固件缺陷（P2，#15）——保持已修复

`controller.c` 的 `finite_array(n->core.position_ned_m, 6)` 已拆成对位置/速度各 3 元素的显式检查；本轮 Flight M6 主机套件 13 + 11 checks / 0 failures 复跑通过。

## 3. 实际执行的测试

| 套件 | 结果 |
|---|---|
| Matalab 完整入口 `run_component_checks` | 19 PASS / 1 PARTIAL（Plant，预期）/ 1 FAIL（`m6_jobs`，仅覆盖率） |
| 26 s MIL 闭环 | 最高 2.0841 m、终速 0.0249 m/s、MPC worker 1300 次、执行器提交 8296 次、三入口回放一致 |
| Flight `tests/control`（M6 组装 + 上下文守卫） | 13 + 11 checks / 0 failures |
| Flight `tests/flight_management`（FMS 主机套件，WSL） | 993 checks / 0 failures |
| Flight `tests/simulation` SIL（构建时） | 4147 checks / 0 failures |
| 归档可靠性 A-01…A-08 | 8/8 PASS |
| 专题实验：三个 26 s MIL 构建（基线 / 仅 `eps_rel=0` / `eps_rel=0`+到期链） | 见 §2.1，原始表格 `work/validation/archives/…/fmat0012_ground_experiment.json` |

## 4. 修改文件清单

**Flight**（`test/fmat-0012-m6-controller`，`b2f33ee`）

- `middleware/model/control/outer_loop/quad_x4/mpc_solver/mpc.c`——到期链移除执行器 TTL；`mpc_use_absolute_termination()` 在 `mpc_reset()` 内把工作区改为绝对终止。

**Flight_Matalab**（`optimize/sil-physical-parameter-alignment`）

- `spec/validation/FMAT-0012-mpc-consumer-path.md`——§4.6/§4.6.1 新增（机制更正、三构建实测、覆盖率三个分母）。
- `config/flight_baseline.json`——随 Flight 源码更新重新录制（两次：第一次对应已被取代的工作区改法，第二次对应最终 `b2f33ee`）。
- 本文件。

**未提交（用户本地生成物，按规范不动）**：`dictionaries/Flight_Parameters.sldd`、`models/**/*.slx`、`scenarios/flight_sil_recording.mat`、`simulation/*.slx`、`tests/g2/models/FMT_PIDAllocationProbe.slx`、未跟踪的 `models/plant/FMT_PlantSensors.slx`。接管时已整份备份到 `work/backup/takeover_20261111T071514/`。

## 5. Issue 状态

| Issue | 本轮动作 | 建议状态 |
|---|---|---|
| #12 M6 成功率/覆盖率 | 两项修复 + 三构建实测；覆盖率口径待裁定 | `BLOCKED`（等口径裁定）；修复本身 `FIXED_WAITING_RETEST` |
| #13 M7 Ground Stop | 执行器侧复跑 PASS；FMS 侧设计待定 | `BLOCKED`（等契约/ACK 决策） |
| #14 P-10b 完整集成 | 复核报告一致性，无新代码 | `IN_PROGRESS`（P-10 仍 `PARTIAL`） |
| #16 归档分类 | A-07/A-08 与分类计数复核通过 | `FIXED_WAITING_RETEST` |
| #17 文档/归档数字 | 22/22 对账通过 | `FIXED_WAITING_RETEST` |
| #15 controller.c 越界 | 主机套件复跑通过 | `FIXED_WAITING_RETEST` |
| #2～#6、#10、#11 | 正文 `Current status` 已是 `VERIFIED`/`FIXED_WAITING_RETEST`，但 GitHub 仍 Open | 建议按 §6 关闭或改状态 |

## 6. 待人工执行的 Issue 更新（本环境无法写 GitHub）

**#12 → `BLOCKED`**（追加评论 + 正文 Current status）：
> 2026-11-11，`IN_PROGRESS → BLOCKED`。修复见 Flight `b2f33ee`（计划有效期移除执行器 5 ms TTL；`mpc_reset()` 改绝对终止），证据 RUN_ID `20261110T235206650Z_78912e8`（ZIP SHA-256 `07575f02…`，`source_clean=true`，claims 22/22）。实测 488/488 job 通过（成功率 100%）、控制路径覆盖 9272/9760（95.0%）、dual residual max 9.995e-4、MIL 2.0841 m 且 TAKEOFF ack=1。阻塞点：验收计划写"有效 MPC 周期 / 闭环时长 ≥90%"，实现用整轮 26 s 做分母，而 `blocked_mode=549/1300`，该分母上限 57.77%，任何实现不可达。需在"整轮 26 s / worker 可用窗口 15.02 s / 1 kHz 消费点"三者中裁定合同口径；裁定前判定口径不动。附：地面段旧根因（MPC 水平指令少 0.20 m/s²）已被三构建实测否证，真实激励是 5 ms 计划寿命导致的 MPC/PD 1 kHz 交替。

**#13 → `BLOCKED`**：
> 2026-11-11，`IN_PROGRESS → BLOCKED`。执行器侧复跑 PASS（230 checks / 0 failures、`ground_stop_transaction=PASS`、100,500 µs ≤ 105,500 µs、DISARMED 后无非零输出），证据 RUN_ID `20261110T235206650Z_78912e8`。FMS 侧两阶段 DISARM 未实施：`fms.c:599-626` 仍在同一 handler 内 `DISARMING → DISARMED`。需要决策：(a) 是否给 `FmsOutputView` 增 `GroundStopCertificate` 并把 `ActuatorCommitReceipt` 送进 `FmsInputs`（跨 A 侧契约、需同步 ICD 与依赖锁）；(b) 还是采用"定时等待 105.5 ms + Mission 侧合成证书"的弱化版（无契约变更，但 FMS 侧不闭环零回执）；(c) DISARM 的 ACK 何时算完成（立即 COMPLETED / 先 ACCEPTED 后由 tracker 完成）。三者都会改变操作员可见语义，需裁定。

**#16、#17、#15 → `FIXED_WAITING_RETEST`**（若尚未置位）：
> 2026-11-11 复核：A-01…A-08 8/8 PASS、`verify_archive_claims.py` 22/22 PASS、`generated_assets_summary` = modified_by_run 5 / pre_existing 4 / commit_candidate 1 / excluded 13。证据 RUN_ID `20261110T235206650Z_78912e8`。

## 7. 下一阶段任务（按依赖顺序）

1. **裁定覆盖率口径（P0，阻断 #12）**：建议采用 1 kHz 消费点口径 `used/samples`（本轮 95.0%），因为它同时满足"PD 回退计入分母"和"闭环时长"两条原文；若确认，改动点只有 `tests/verify_m6_jobs.m` 的分母与 `m6_report.json` 的 `coverage_basis.gate_denominator`，并需同步 `spec/validation/FMAT-0012-m6-acceptance-plan.md` §2.2 的措辞。不得同时放宽 90% 阈值。
2. **M7 FMS 两阶段 DISARM（P0，等 §6 #13 的决策）**：三种可行路径见 #13 文案。改后必须重跑 FMS 主机套件（基线 993/0）、Flight M7 套件与完整 MATLAB 回归。
3. **P-10b（P1，#14）**：真实 UART/DMA 与 `sensor_gnss_poll` 端到端接入 Host SIL，再区分板级证据。这是实现工作，不是文档工作。
4. **旧 Issue 收口（P2）**：#2、#3、#4、#6、#10、#11 正文已是 `VERIFIED`，若确认无回归可按关闭清单关闭；#5 仍是 `FIXED_WAITING_RETEST`。

## 8. 边界声明

- 本轮全部结果来自 PC MATLAB/Simulink（R2026b Update 1）+ Windows Host SIL，**不构成 H723 实机、PIL/HIL 或实飞验证**；
- 未实测项一律保持 `NOT_RUN`/`PARTIAL`，没有以"应该可以"替代证据；
- 未放宽任何门限（1e-3 残差门限、99% 成功率、90% 覆盖率阈值与判定分母均未改），未跳过候选解验证，未延长旧解有效期，未修改 Plant 物理，未修改 `main`，未合并任何 PR；
- 专题实验的三个构建中，只有最终两项修复保留在 Flight；"仅 `eps_rel=0`" 与"改生成工作区"两种中间形态均已回退。
