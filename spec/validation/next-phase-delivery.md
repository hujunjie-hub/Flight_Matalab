# 当前 main 接管状态（2026-11-14）

> **本节为当前有效基线；下方原始交付记录保留作历史追溯。** 下方记录中的旧开发分支、PR Draft 状态和旧测试 HEAD 不再是当前拉取/验收目标。当前唯一工作分支为 main。操作步骤以 [本地 MATLAB 验证交接说明](LOCAL_MATLAB_HANDOFF.md) 为准。

## 当前仓库基线

| 项 | 当前结论 |
|---|---|
| GitHub 仓库 | hujunjie-hub/Flight_Matlab |
| 工作分支 | main（当前只保留 main） |
| 接管起点 HEAD | 0cdfe3a41432834d424e4ecceec37977ffe837d5 |
| PR #1 | 已合并；不得再按旧记录中的 Draft 状态处理 |
| MATLAB 对当前 main 的完整复测 | NOT_RUN；必须由用户本地拉取最新 main 执行 |
| 最近一份历史完整 MATLAB 归档 | RUN_ID 20261113T092308651Z_34e57d0；当时测试的是合并前分支 commit 34e57d0，不是当前 main HEAD |
| implementation_manifest.json | BASELINE_EVIDENCE_STALE_REQUIRES_REFRESH；不得作为当前 main 的 PASS 证据 |
| 本地运行交接 | [LOCAL_MATLAB_HANDOFF.md](LOCAL_MATLAB_HANDOFF.md) |

## 2026-11-14 上游 Flight/main 同步复核

本节覆盖前述 2026-11-13 历史归档之后的上游变化，优先级高于历史交付记录：

- 当前核对的 Flight/main 为 e470f00cd539f438b1923b0faa844456ba2d3b59。历史文档所引用的 1c7a72a 已落后 618 个提交；不能继续将该 commit 或它的 MATLAB 归档当作当前配套固件证据。
- 这段上游变化涉及 applications/runtime/runtime_data.c、runtime_internal.h、Mission/Actuator task、MPC 和 FMS 等运行路径。必须在本地使用当前 Flight/main 重建 Host SIL 并重新运行完整 MATLAB 验收。
- external_dependencies.lock.json 已更新为当前 Flight/main 的两个契约头 SHA-256，以及 OSQP UPSTREAM_LOCK.json 的规范化 CRLF SHA-256 91e6b16fbd39a1f8e407bb9056d82adbea192b45f2673e5855377b2c94cde37e；当前锁覆盖 42 个运行时文件（此前为 47）。OSQP/qdldl 上游版本和来源仍保持 v1.0.0 / v0.1.8。
- 当前 Flight abi_lock.h 的生成清单为 144 types / 993 fields，新增项是 GroundStopCertificate（message registry ID 56，112 bytes / 7 fields）。但已提交的 tests/abi/evidence/abi_report.md 仍报告 143 / 986 和旧 registry SHA，与 abi_lock.h 不一致。Schema 6.0 / Product-Port 0x00010906 未变；上游需重新生成 ARM/Host ABI 报告并完成 revision review。见 FMAT-0018。
- config/flight_baseline.json 的旧 sources_sha256 是历史记录。标准 run_component_checks 会先构建 Flight Host SIL 并重新记录当前源文件，再由 build_native_kernels 执行 verify_inputs.py。预检 PASS 才能继续 MATLAB gate。
- 当前 main 的 MATLAB/Simulink 完整复测仍为 NOT_RUN。本轮锁文件和运行入口的修改只属于静态/仓库层变更，不构成 MATLAB 编译或仿真通过。

## 本轮代码与验证门禁更新

1. M6 runtime stats 新增 schema 标识 fmat-m6-runtime-stats/1.0，避免误读旧格式统计文件。
2. verify_m6_jobs 增加 fail-closed 校验：零 job 保持 NOT_RUN 并使完整验收失败；统计计数必须是有限非负整数；solved + rejected 必须等于 jobs；covered_us 不得超过整轮时长；逐 job 记录必须存在、schema 正确、记录数量与 job 数一致、job ID 必须完整覆盖 1..jobs、outcome 在定义范围内且 solved/rejected 必须与逐 job outcome 汇总一致。
3. 新增 verify_m6_jobs_contract，并接入 run_component_checks，使用隔离临时目录覆盖有效 100-job、零 job、缺失记录、aggregate counter mismatch、aggregate-vs-outcome mismatch、非连续 job ID、covered_us 记账不一致、覆盖时间越界和旧 schema 九类情况。verify_m6_jobs 还要求 outcome=OK 的数量等于 solved，其余 outcome 数量等于 rejected，job ID 必须完整连续 1..N，且 covered_us 必须等于 solved × 20,000 us（Flight mpc.c 每个成功 job 记账一个 20 ms 周期）。
4. external_dependencies.lock.json 已由 commit 249d8a3 对齐 Flight/main 的 product contract headers 与 OSQP runtime lock（42 个运行时文件）；run_component_checks 在 build_native_kernels 后读取 input_preflight.json 并将其纳入 component_checks.checks，缺失或非 PASS 会阻断。
5. tools/write_implementation_manifest.py 已修正证据状态合同：input_preflight/flight_entries/cold_start 必须 PASS，Plant 必须 PARTIAL、component_checks 必须 PARTIAL_PASS，并校验 M6 与 P-10b gate；生成状态为 PARTIAL_PASS_HOST_SIL，不再错误要求所有子报告均为 PASS。
6. 上述 MATLAB/Simulink 代码尚未在当前环境执行。它们只有在用户本地运行完整 run_component_checks 并归档后才可标记为通过。

**未改变的验收合同：** FMAT-0012 的 90% 覆盖率门槛和当前整轮分母保持不变；不改变 MPC 求解容差、不改变消费策略、不更改 Flight 公共接口。等待用户明确裁定后才处理统计分母。

## 当前未闭合问题

| Issue | 当前状态 | 本轮处理边界 |
|---|---|---|
| #12 / FMAT-0012 | BLOCKED | 488/488 MPC jobs、95.0% 消费点使用率已有历史证据；整轮口径 37.54%，等待用户确认合同分母。当前代码仍按整轮口径判定，不得自行改为消费点口径 |
| #13 / FMAT-0013 | BLOCKED | Flight M7 执行器侧证书→限速降推力→ZERO_TARGET_APPLIED 回执已有 230/230 Host 检查；但 fms_build_ground_stop_certificate 要求快照已是 DISARMED，而 PRODUCT_CMD_DISARM 在同一 handler 内从 DISARMING 直接转 DISARMED 并返回 COMPLETED，未等待真实回执。等待用户批准公共契约/异步 ACK 语义；批准前不改 ICD/ABI，闭环实现后再补本项目 Host MIL 端到端断言 |
| #14 / FMAT-0014 | IN_PROGRESS | Host 时间服务/GNSS 核心测试与真实 TIM2、UART/DMA、sensor_gnss_poll 和板级证据分开；P-10 overall 保持 PARTIAL |
| #15 / FMAT-0015 | FIXED_WAITING_RETEST | 上游数组边界修复已有结构化测试；等待当前配套基线的本地复测确认 |
| #16 / FMAT-0016 | VERIFIED（Issue 仍 Open） | 归档分类有历史 8/8 证据；当前 main 回归后再结案 |
| #17 / FMAT-0017 | VERIFIED（Issue 仍 Open） | P-10b 同 RUN_ID 对账有历史证据；当前 main 回归后再结案 |
| #18 / FMAT-0018 | BLOCKED | Flight/main 比旧配套基线前进 618 个提交；GroundStopCertificate 是已存在类型新纳入 registry/ABI inventory，当前 lock 为 144/993，但 ARM/Host/compare 仍是 143/986、55 messages。须重跑 ABI 证据并审查 Product/Port revision policy；当前 MATLAB/Simulink 配套回归也未完成 |
| #19 / FMAT-0019 | FIXED_WAITING_RETEST | M6 汇总 solved/rejected 与逐 job outcome 对账、covered_us=solved×20,000 us、job ID 连续性检查已提交；新增三项负向测试，等待本地 MATLAB 回归 |

#12、#13 的用户决策仍是阻塞条件；继续处理与其无依赖的代码、测试和文档，不得绕过决策。#14 的 Host 核心通过不能替代板级证据。

## 用户下一步

按 [本地 MATLAB 验证交接说明](LOCAL_MATLAB_HANDOFF.md) 执行。必须交回 RUN_ID ZIP、同名 SHA-256 校验文件、Flight_Matlab/Flight 两个 commit、MATLAB Release 和完整组件总状态；若 Host SIL 重建修改了 config/flight_baseline.json，还必须把该文件单独发回，不要自行提交。不要单独发送截图代替归档。

---

# 下一阶段交付清单（截至 RUN_ID `20261113T092308651Z_34e57d0`）

## 0. 新会话接管必读（2026-11-13 同步后交接）

本轮在 2026-11-13 把 Flight_Matalab 同步到已更新的 Flight 上游（`b2f33ee` → `1c7a72a`，43 个提交），并重跑完整回归。新会话**不要**从聊天摘要续接，按下面顺序核对。

**基线**

| 项 | 值 |
|---|---|
| Flight_Matalab | `optimize/sil-physical-parameter-alignment`，归档针对 `34e57d0`（Draft PR #1；其后的提交只修改本交付文档，归档**未**声称测试它们） |
| Flight 上游 | `test/fmat-0012-m6-controller` @ `1c7a72a`（M7 FMS→执行器地面停止证书链、异步帧应用、M6 截止时间记账、CI 门；含本会话 `b2f33ee` 的 M6 计划寿命/绝对终止修复并被加固） |
| 最后归档 | `work/validation/archives/20261113T092308651Z_34e57d0.zip`，SHA-256 `303198ebc0730c98fe3584a97790e1803b9b0219afed22375e214fa1b3203d8d`，`source_clean=true`，47 个证据文件 |
| 归档自对账 | `python tools/verify_archive_claims.py --run-id 20261113T092308651Z_34e57d0` → **22/22 PASS** |
| 被取代的归档 | `20261110T235206650Z_78912e8`（上一基线）、`20261110T234422185Z_78912e8`（归档时 HEAD 已被文档提交推进，`21/22`）；保留不删，**不得**作为当前验收证据引用 |

**本次同步做了什么**

1. `config/flight_baseline.json` 重新录制：Flight 源文件 483 → **484**（新增 `middleware/model/fms/quad_x4/flight_safety/ground_stop_adapter.c`），所有受影响哈希更新。
2. `external_dependencies.lock.json` 重新钉住 OSQP 运行时锁：新锁记录 qdldl v0.1.8 来源并声明 `hash_newlines: canonical CRLF`；`osqp.source_lock` 同步 `transitive_sources`，`runtime_lock_sha256` → `1f193ed2…`。
3. `tools/verify_inputs.py` 按该声明做**规范化换行后取哈希**，47 个运行时文件仍逐个校验，并新增"锁覆盖文件数必须等于 `verified_files`"的断言。这是跨平台一致性修复，不是放宽校验。
4. 重建 Host SIL（Flight SIL 4147 checks / 0 failures）、参数字典、Plant/Flight/Actuation 模型，再跑完整 `run_component_checks`。

**本次回归实测**

| 项 | 值 |
|---|---|
| `component_status` | **FAIL**（19 PASS、1 PARTIAL（Plant，预期）；FAIL 仅 `m6_jobs` 的覆盖率分母） |
| M6 | 488/488 job 通过（成功率 100%），消费点 9272/9760（**95.0%**），整轮口径 37.54% |
| M7 | 主机套件 230 checks / 0 failures，`ground_stop_transaction=PASS`、105,500 µs |
| MIL | `flight_entries=PASS`，最高 2.0829 m，终速 0.0118 m/s，三入口回放一致 |
| P-10b | 各子门 PASS，整体仍 `PARTIAL`（板级证据缺失） |

**仍未闭合**

1. **覆盖率口径（P0，阻断 #12 结案）**：验收计划写"有效 MPC 周期 / **闭环时长** ≥90%"，实现用**整轮 26 s**；`blocked_mode=549/1300` 使该分母上限只有 **57.8%**，任何实现不可达。三种口径与推荐见 §2.1 与 §9.3 决策 A。
2. **M7 FMS 两阶段 DISARM（P0，#13）**：Flight 侧已按 §9.3 决策 B 实现证书→应用→回执链（`36321bd`、`ef10fd4`、`f28b7b7`），本项目的 M7 门与 SIL 已复跑通过；仍需你确认该设计即合同口径，并补 FMS 侧"等真实零回执再转 DISARMED"的端到端断言（当前证据来自固件套件，不是本项目的 Host MIL 断言）。
3. **P-10b 板级链路**：真实 TIM2 capture、UM982 UART/DMA、`sensor_gnss_poll` 与板级时钟仍未实现/未测。

**三条已知陷阱（会浪费一整轮）**

- 状态帧**第 75～108 列是 `FAILSAFE_TERMINAL` 的终端锁存值**，不是实时 land 状态；不要用它判断 landed。
- `config/flight_baseline.json` 会被重建 Host SIL 改写：**先在 `../Flight` 提交/更新源码，再重建、提交该文件，最后才跑完整回归**，否则 `source_clean=false`。
- Flight 仓库 `core.autocrlf=true` 且无 `.gitattributes`：`git checkout` 会把 LF 改成 CRLF。恢复生成文件用 `git checkout <rev> -- <path>`；OSQP 运行时哈希按 `hash_newlines=canonical CRLF` 计算，不要用裸哈希判断。**新增的 `tests/**/*.sh` 在本机检出后是 CRLF，WSL 直接跑会报 `set: pipefail: invalid option name`**；不要为此改动 Flight 工作树（会破坏 baseline 哈希），用 `sed 's/\r$//' <script> > build/<name>.sh` 后从仓库根执行（脚本靠向上找 `SConstruct` 定位根目录，放在 `build/` 里不影响）。

**第一条命令**

```powershell
git -C E:\Flight\Flight_Matlab_Test status --short; git -C E:\Flight\Flight_Matlab_Test rev-parse HEAD
git -C E:\Flight status --short; git -C E:\Flight rev-parse HEAD
python -B tools\verify_archive_claims.py --run-id 20261113T092308651Z_34e57d0
python -B tools\verify_inputs.py
pwsh -NoProfile -File .\tools\build_flight_runtime.ps1 -GccDir 'D:\STM32CubeCLT\mingw64\bin'
```

> **BLOCKER_STATUS: BLOCKED（2 项）**
> 1. **覆盖率合同口径未定**（[Issue #12](https://github.com/hujunjie-hub/Flight_Matalab/issues/12)）：分母数学上不可达 90%，需用户裁定（§9.3 决策 A）；裁定前 `verify_m6_jobs.m` 判定口径不动，`component_checks.status` 只能是 FAIL。
> 2. **M7 DISARM 闭环的合同确认**（[Issue #13](https://github.com/hujunjie-hub/Flight_Matalab/issues/13)）：固件已实现决策 B 的证书+回执链，需确认设计并补 FMS 侧端到端断言；本会话只做消费侧验证，不改 Flight 公共接口。
>
> 说明：本会话环境仍无 GitHub 写权限；Issue 状态由 Integration Owner 维护（§6）。

## 1. 交付物

| 项目 | 值 |
|---|---|
| RUN_ID | `20261113T092308651Z_34e57d0` |
| ZIP | `work/validation/archives/20261113T092308651Z_34e57d0.zip`（47 个证据文件） |
| ZIP SHA-256 | `303198ebc0730c98fe3584a97790e1803b9b0219afed22375e214fa1b3203d8d` |
| `component_status` | **FAIL**（19 PASS、1 PARTIAL；FAIL 只有 `m6_jobs`，且只差覆盖率分母） |
| source 指纹（磁盘） | `5402d81cde925cb0e157af1ad8a8c2ccf39aafe33739eb27a73faba40bc26421` |
| source 指纹（committed） | `c9deb905af53eeaccc3ee6da490739898cbda2b7ff49561bd40faa90124d75ef` |
| artifact 指纹 | `9248b244e56a1e87d021e9fecf7796903528b2c4f35aa3409f095b2b14593226` |
| `source_clean` | true（Flight_Matalab `34e57d0`，Flight `1c7a72a`） |
| 生成文件分类 | `pre_existing_local_change_modified_by_run` 5、`pre_existing_local_change` 4、`commit_candidate` 1、`excluded_from_source` 13 |
| PR 状态 | Flight_Matalab#1 Draft；`main` 未改动 |
| 重复性 | M6 计数在同一 Flight commit 上与前一轮一致（488/488、9272/9760），dual median 8.397e-4 vs 8.316e-4（求解器数值路径微差，均 <1e-3） |

## 2. 本轮实际结果

### 2.1 M6 MPC（P0，#12）——修复完成，只剩覆盖率口径

**修复（Flight `b2f33ee`，`mpc.c` 两处；在 `1c7a72a` 中被上游保留并加固）**

1. **计划有效期不再被 5 ms 执行器消息 TTL 掐住**：`actuator_capability/status` 的 `valid_until_us` 从到期取 min 链中移除。两者都不进入 QP，5 ms 是遥测新鲜度契约，不是计划有效期；此前它把计划压到 20 ms 周期的四分之一。
2. **求解器改绝对终止**：`mpc_reset()` 用 `osqp_update_settings()` 把工作区 `eps_rel` 置 0（`eps_abs` 仍 1e-3），使 OSQP 满足应用侧**未改动**的绝对 1e-3 双残差门限。`1c7a72a` 把该函数改为返回 `Status` 并在失败时拒绝初始化控制器（`control_backend_init` 置 `MODULE_HEALTH_FAILED`），比原实现更严格。

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
| 26 s MIL | 2.0982 m，TAKEOFF ack=1 | **2.0829 m，TAKEOFF/ARM/LAND/DISARM 全部 ack=1**，终速 0.0118 m/s，三入口回放一致 |

**覆盖率口径（需裁定）**

| 口径 | 本轮值 | 结构上限 | 备注 |
|---|---|---|---|
| 整轮 26 s（**当前判定口径**） | 37.54% | **57.77%** | `blocked_mode=549`，751 个可尝试 tick；任何实现都到不了 90% |
| worker 可用窗口 15.02 s | 64.98% | 100% | 仍受 `blocked_validation=263` 影响 |
| 1 kHz 消费点 `used/samples` | **95.00%** | 100% | 直接测量"控制路径上 MPC 接管了多少时间"，PD 回退计入分母 |

`fallback_counted_as_uncovered` 在三种口径下都成立，因此切到消费点口径不是放宽门限，而是把分母改回"闭环时长"的原意。**这是验收标准变更，Agent 未执行。**

**地面段机制更正（详见[附记 §4.6](FMAT-0012-mpc-consumer-path.md)）**

旧结论（"MPC 水平指令比 PD 少 0.2038 m/s²，把飞行器推到 0.58 m/s"）被三个构建的实测否证：滑移方向上位置环在**刹车**（5.4 s 时 PD +1.026、MPC +0.799 m/s²，而飞行器沿 −x 漂移）；水平加速度 100% 由倾斜推力解释（最大残差 0.040 m/s²）；地面俯仰与指令**反向**（指令 −0.6…−11.0°，实测 +5.35°）。真实激励是 8 ms 计划寿命造成的 MPC/PD 每 20 ms 数次切换；寿命修好后占空比 0.8%→95%，俯仰落在 −0.46…0°，地面 `|v_h|` 0.58→0.046 m/s。

### 2.2 M7 Ground Stop（P0，#13）——执行器侧 PASS，FMS 证书链已由固件侧落地

| 项目 | 本轮实测（RUN_ID `20261113T092308651Z_34e57d0`） |
|---|---|
| `ground_stop_transaction` | PASS（`FIRMWARE_GROUND_STOP_CERTIFICATE`） |
| 最坏应用时间 | 105,500 µs（套房自报上限，实测段见前轮 100,500 µs） |
| 最大降推力速率 | 100 N/s |
| 零回执后才 DISARMED | 执行器侧 PASS；DISARMED 后无非零输出 |
| Flight M7 主机套件 | 230 checks / 0 failures |
| Flight SIL（构建时） | 4147 checks / 0 failures（含新增 FMS→M7 地面停止链路用例） |

**同步带来的变化**：Flight `1c7a72a` 已按 §9.3 决策 B 实现 FMS 侧证书链——`36321bd feat(fms): translate ground disarm into M7 stop certificate`、`ef10fd4 feat(runtime): route FMS ground-stop certificate to M7`、`f28b7b7 test(sil): exercise live FMS request-to-actuator ground stop`，并新增 `middleware/model/fms/quad_x4/flight_safety/ground_stop_adapter.c`（Flight M4 套件 `31edd08` 覆盖真实证书输出）。

**仍未完成的部分（属于本项目证据）**：本项目只验证到"固件套件 + SIL 已跑通该链路"，**没有**在本项目的 Host MIL 里逐帧断言"FMS 从 DISARMING 等到真实 `ZERO_TARGET_APPLIED` 回执才转 DISARMED"。该断言需要读取 FMS 输出与执行器回执的对应关系，属本项目新增测试；在补上之前 #13 不能按端到端结论处置。

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
- `verify_archive_claims.py --run-id 20261113T092308651Z_34e57d0` → **22/22 PASS**。
- P-10b 文档数字与原始 ZIP 数字一致（21/1/21/21、epoch 11、12 intervals）。

### 2.5 固件缺陷（P2，#15）——保持已修复

`controller.c` 的 `finite_array(n->core.position_ned_m, 6)` 已拆成对位置/速度各 3 元素的显式检查；本轮 Flight M6 主机套件扩充为 15 + 26 = **41 checks / 0 failures**（固件侧已补结构化边界夹具），复跑通过。

## 3. 实际执行的测试

| 套件 | 结果 |
|---|---|
| Matalab 完整入口 `run_component_checks` | 19 PASS / 1 PARTIAL（Plant，预期）/ 1 FAIL（`m6_jobs`，仅覆盖率） |
| 26 s MIL 闭环 | 最高 2.0829 m、终速 0.0118 m/s、MPC worker 1300 次、执行器提交 8311 次、三入口回放一致 |
| Flight `tests/control`（M6 组装 + 上下文守卫） | 15 + 26 = **41 checks / 0 failures**（同步前为 13+11） |
| Flight `tests/flight_management`（FMS 主机套件，WSL） | **1002 checks / 0 failures**（同步前 993；新增 M4 地面停止证书用例） |
| Flight `tests/simulation` SIL（构建时） | 4147 checks / 0 failures |
| Flight `tests/actuation`（M7，经组件门） | 230 checks / 0 failures |
| 归档可靠性 A-01…A-08 | 8/8 PASS |
| 专题实验：三个 26 s MIL 构建（基线 / 仅 `eps_rel=0` / `eps_rel=0`+到期链） | 见 §2.1，原始表格在上轮归档的 `fmat0012_ground_experiment.json` |

## 4. 修改文件清单

**Flight**（`test/fmat-0012-m6-controller` @ `1c7a72a`，含 `b2f33ee`）

- `middleware/model/control/outer_loop/quad_x4/mpc_solver/mpc.c`——到期链移除执行器 TTL；`mpc_use_absolute_termination()` 在 `mpc_reset()` 内把工作区改为绝对终止（`1c7a72a` 加固为返回 `Status`）。
- 上游后续 43 个提交（M7 证书链、异步帧应用、M6 截止时间记账、CI 门、OSQP 锁规范化）——本项目只消费，不修改。

**Flight_Matalab**（`optimize/sil-physical-parameter-alignment`）

- `config/flight_baseline.json`——按 `1c7a72a` 重新录制（484 个 Flight 源文件）。
- `external_dependencies.lock.json`——OSQP 运行时锁重新钉住（`runtime_lock_sha256`=`1f193ed2…`，`source_lock.transitive_sources` 记录 qdldl v0.1.8）。
- `tools/verify_inputs.py`——按 `hash_newlines=canonical CRLF` 规范化后校验 47 个运行时文件，并新增文件数断言。
- `spec/validation/FMAT-0012-mpc-consumer-path.md`——§4.6/§4.6.1（机制更正、三构建实测、覆盖率三个分母）。
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

## 6. GitHub Issue 状态已同步（2026-11-11）

> **2026-11-13 追加（同步 Flight `1c7a72a` 后）：** 新证据 RUN_ID `20261113T092308651Z_34e57d0`（ZIP SHA-256 `303198eb…`，`source_clean=true`，claims 22/22，Flight `1c7a72a`）。M6 仍 488/488、消费点 9272/9760（95.0%）、整轮口径 37.54%，`component_status=FAIL` 仅因覆盖率分母；M7 主机套件 230 checks/0 failures、`ground_stop_transaction=PASS`，且固件已落地证书→应用→回执链。**#12 仍等决策 A；#13 从"等设计批准"改为"等本项目 Host MIL 端到端断言 + 用户确认设计 B"。**

> **同步结果：** 已将最新证据和处理卡实际写入 GitHub Issues。当前状态以 Issue 正文顶部的 Current status 为准：#12 BLOCKED、#13 BLOCKED、#14 IN_PROGRESS、#15 FIXED_WAITING_RETEST、#16 VERIFIED、#17 VERIFIED。下方原“待人工执行”内容保留为本轮状态迁移说明，不再要求用户手工复制更新。


**#12 → `BLOCKED`**（追加评论 + 正文 Current status）：
> 2026-11-11，`IN_PROGRESS → BLOCKED`。修复见 Flight `b2f33ee`（计划有效期移除执行器 5 ms TTL；`mpc_reset()` 改绝对终止），证据 RUN_ID `20261110T235206650Z_78912e8`（ZIP SHA-256 `07575f02…`，`source_clean=true`，claims 22/22）。实测 488/488 job 通过（成功率 100%）、控制路径覆盖 9272/9760（95.0%）、dual residual max 9.995e-4、MIL 2.0841 m 且 TAKEOFF ack=1。阻塞点：验收计划写"有效 MPC 周期 / 闭环时长 ≥90%"，实现用整轮 26 s 做分母，而 `blocked_mode=549/1300`，该分母上限 57.77%，任何实现不可达。需在"整轮 26 s / worker 可用窗口 15.02 s / 1 kHz 消费点"三者中裁定合同口径；裁定前判定口径不动。附：地面段旧根因（MPC 水平指令少 0.20 m/s²）已被三构建实测否证，真实激励是 5 ms 计划寿命导致的 MPC/PD 1 kHz 交替。

**#13 → `BLOCKED`**：
> 2026-11-11，`IN_PROGRESS → BLOCKED`。执行器侧复跑 PASS（230 checks / 0 failures、`ground_stop_transaction=PASS`、100,500 µs ≤ 105,500 µs、DISARMED 后无非零输出），证据 RUN_ID `20261110T235206650Z_78912e8`。FMS 侧两阶段 DISARM 未实施：`fms.c:599-626` 仍在同一 handler 内 `DISARMING → DISARMED`。需要决策：(a) 是否给 `FmsOutputView` 增 `GroundStopCertificate` 并把 `ActuatorCommitReceipt` 送进 `FmsInputs`（跨 A 侧契约、需同步 ICD 与依赖锁）；(b) 还是采用"定时等待 105.5 ms + Mission 侧合成证书"的弱化版（无契约变更，但 FMS 侧不闭环零回执）；(c) DISARM 的 ACK 何时算完成（立即 COMPLETED / 先 ACCEPTED 后由 tracker 完成）。三者都会改变操作员可见语义，需裁定。

**#16、#17、#15 → `FIXED_WAITING_RETEST`**（若尚未置位）：
> 2026-11-11 复核：A-01…A-08 8/8 PASS、`verify_archive_claims.py` 22/22 PASS、`generated_assets_summary` = modified_by_run 5 / pre_existing 4 / commit_candidate 1 / excluded 13。证据 RUN_ID `20261110T235206650Z_78912e8`。

## 7. 下一阶段任务（按依赖顺序）

1. **裁定覆盖率口径（P0，阻断 #12）**：建议采用 1 kHz 消费点口径 `used/samples`（本轮 95.0%），因为它同时满足"PD 回退计入分母"和"闭环时长"两条原文；若确认，改动点只有 `tests/verify_m6_jobs.m` 的分母与 `m6_report.json` 的 `coverage_basis.gate_denominator`，并需同步 `spec/validation/FMAT-0012-m6-acceptance-plan.md` §2.2 的措辞。不得同时放宽 90% 阈值。
2. **M7 端到端断言（P0，本项目侧）**：固件已在 `1c7a72a` 落地证书→应用→回执链（决策 B），本项目需补一条 Host MIL 断言：FMS 在 `DISARMING` 期间的任务许可为撤销态、证书生命周期间停止输出单调下降、只有收到 `ACTUATOR_RECEIPT_ZERO_TARGET_APPLIED` 后才出现 `ARM_STATE_DISARMED`，且此后无任何非零推力码。补上后再请用户确认 #13 的端到端结论。
3. **P-10b（P1，#14）**：真实 UART/DMA 与 `sensor_gnss_poll` 端到端接入 Host SIL，再区分板级证据。这是实现工作，不是文档工作。
4. **旧 Issue 收口（P2）**：#2、#3、#4、#6、#10、#11 正文已是 `VERIFIED`，若确认无回归可按关闭清单关闭；#5 仍是 `FIXED_WAITING_RETEST`。

## 8. 边界声明

- 本轮全部结果来自 PC MATLAB/Simulink（R2026b Update 1）+ Windows Host SIL，**不构成 H723 实机、PIL/HIL 或实飞验证**；
- 未实测项一律保持 `NOT_RUN`/`PARTIAL`，没有以"应该可以"替代证据；
- 未放宽任何门限（1e-3 残差门限、99% 成功率、90% 覆盖率阈值与判定分母均未改），未跳过候选解验证，未延长旧解有效期，未修改 Plant 物理，未修改 `main`，未合并任何 PR；
- 专题实验的三个构建中，只有最终两项修复保留在 Flight；"仅 `eps_rel=0`" 与"改生成工作区"两种中间形态均已回退。


## 9. 阻塞处理卡与任务分发（2026-11-11）

### 9.1 本轮统一证据基线

> **已被 2026-11-13 同步取代。** 当前基线见 §0/§1（RUN_ID `20261113T092308651Z_34e57d0`、Flight `1c7a72a`、Matalab `34e57d0`）。下面保留 2026-11-11 记录用于追溯。

- RUN_ID：`20261110T235206650Z_78912e8`
- ZIP SHA-256：`07575f020d77431f49a60360cffc9823059a029358a354a01f2838558ad704c1`
- Flight_Matalab tested commit：`78912e86b6cd51b82800a6eb1ad5bb7773a4739e`
- Flight upstream：`b2f33ee00fd7cc36fb51803d38ab0ff1267cbf0f`
- PR #1 HEAD：`f95c2ae502d6e40b6d7531be42b323e5776a86b2`，仅比测试归档多 1 个修改本交付文档的提交；归档未声称测试该文档提交。
- 归档结果：19 PASS / 1 PARTIAL（Plant，预期）/ 1 FAIL（M6 coverage_90）。
- 本地 worktree 仍有 10 项用户本地模型/字典/录制文件修改；备份位于 `work/backup/takeover_20261111T071514/`。任何 Agent 不得 reset/clean/覆盖这些文件。

### 9.2 最新阻塞与任务分配

| FMAT | 状态 | Owner | 当前阻塞 | 下一步 |
|---|---|---|---|---|
| #12 M6 | BLOCKED | Flight_Matalab-Agent（待用户确认后） | 488/488 求解成功，但覆盖率分母口径导致 37.54% FAIL；消费点实测 95.0% | 等用户确认 1 kHz consumer denominator；确认前只准备定义和反例测试，不改 gate |
| #13 M7 | BLOCKED → 待本项目端到端断言 | Flight-Firmware-Agent（已交付）+ Flight_Matalab-Agent（验证） | 固件 `1c7a72a` 已实现证书+回执链并通过 M4/M7/SIL 套件；本项目尚无 Host MIL 逐帧断言 | 本项目补 `DISARMING`→真实零回执→`DISARMED` 的 MIL 断言，再请用户确认设计 |
| #14 P-10b | IN_PROGRESS | Flight-Firmware-Agent + Flight_Matalab-Agent（串行接口交接） | Host 核心 PASS，但真实 DMA/parser/poll Host MIL 路径及 H723 板级证据缺失 | Flight 冻结接口后，Matalab 接入 Host DMA-ring adapter；硬件证据独立执行 |
| #15 数组边界 | FIXED_WAITING_RETEST | Flight-Firmware-Agent | 代码已改为两个 3 元素检查，需专门边界测试 | 增加 canary/ASan 或结构化 fixture，再跑 M6 Host tests |
| #16 归档分类 | VERIFIED | 无新增分派 | A-01…A-08 8/8 PASS | 仅在新回归时重开 |
| #17 P-10b 文档对账 | VERIFIED | 无新增分派 | 同 RUN_ID 原始 JSON 与交付文档一致 | 仅在新回归时重开 |

### 9.3 两项需要用户确认的推荐决策

**决策 A — M6 覆盖率合同（FMAT-0012）**

推荐：将 90% 覆盖率定义为 1 kHz 控制消费点的 MPC 实际使用样本数 / 全部控制消费点样本数；PD fallback 必须计入分母。保留整轮 26 s 和 worker 可用窗口指标作为诊断值。成功率 99%、最少 100 jobs、残差 1e-3 和 90% 门槛均不降低。该定义更直接测量控制路径由 MPC 接管的实际时间，也不会通过剔除 fallback 制造 PASS。

**决策 B — M7 DISARM 闭环（FMAT-0013）**

推荐：采用 FMS GroundStopCertificate → Actuator 实际应用 stop code 0 → ActuatorCommitReceipt(ZERO_TARGET_APPLIED) 回传 FMS → FMS 才从 DISARMING 转 DISARMED。命令 ACK 先 ACCEPTED，真实回执完成后再 COMPLETED。拒绝仅等待固定时长后由 Mission 合成证书的弱化方案。

### 9.4 执行顺序和并行边界

1. 用户先确认决策 A/B；未确认前两个 Issue 均保持 BLOCKED，Agent 不得修改验收分母或公共 ABI。
2. Flight-Firmware-Agent 可独立继续 #14 的驱动/时间服务接口设计，以及 #15 的边界测试；#13 只提交设计提案，等待批准。
3. Flight_Matalab-Agent 可独立继续 #14 的 Host MIL 适配设计，但必须等待 Flight 接口/commit 冻结后才接入共享链路。
4. #12 的验收脚本变更必须等决策 A；不得与 Flight 固件 Agent 并行修改同一控制接口。
5. #16/#17 已 VERIFIED，不重复开发或重跑；#14 的 P-10 overall 在 H723 板级证据齐全前保持 PARTIAL。

每个 Agent 只接收其 Owner 范围内的文件和任务；跨仓库接口只有 Flight-Firmware-Agent 能修改，Flight_Matalab-Agent 消费固定版本。任何共享文件只允许一个写入 Owner。

### 9.5 阻塞上报要求

每次任务分发前，先在对应 Issue 写入“推荐方案、精确步骤、Owner、依赖、禁止事项、测试命令、验收门槛和解除条件”。Agent 若无法执行，必须在同一 Issue 评论中提供错误日志、复现命令、已尝试方案和下一步建议；不允许只报告“卡住了”。
