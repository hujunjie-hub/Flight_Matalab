# 下一阶段交付清单（截至 RUN_ID `20261110T140933221Z_e93302d`）

本文件汇总本轮五个阶段的实际产出、证据位置与未闭合项。所有数字均来自同一轮 `run_component_checks`，不是多轮拼接。

## 1. 交付物

| 项目 | 值 |
|---|---|
| RUN_ID | `20261110T140933221Z_e93302d` |
| ZIP | `work/validation/archives/20261110T140933221Z_e93302d.zip`（38 个证据文件） |
| ZIP SHA-256 | `3b4a18b90ac64f4e7904e50b96b0545e56f0527b6658babfd8c1a836409613e1` |
| 大小 | 7.56 MB |
| `component_status` | **FAIL**（15 PASS / 1 PARTIAL / 1 FAIL） |
| source 指纹 | `b4ed29d4c8856d30bc074bc4532abf906557f1acc77a57db8b9e9b7b99fd5c2c`（committed `b40d1c20…`） |
| artifact 指纹 | `b973cb0a9b03b430bc7b282ce64ebac41b9ce4dc481a8c75107212516073c643` |
| `source_clean` | true |
| Flight_Matalab HEAD | `e93302d`（与归档记录的 commit 一致，工作树干净） |
| Flight HEAD | `125773b`（分支 `test/fmat-0012-m6-controller`，工作树干净） |
| PR 状态 | Flight_Matalab#1 Draft；Flight#3 Draft；Flight#4 Draft；`main` 未改动 |

## 2. 各阶段实际结果

### 2.1 阶段一：验收归档可靠性（P0）——完成

| 要求 | 证据 |
|---|---|
| 运行前 source fingerprint | `source_fingerprint_before.json` / `current_source_fingerprint.json`，schema `flight-matalab-source-fingerprint/2.0` |
| 独立 artifact fingerprint | `artifact_fingerprint_before.json` / `current_artifact_fingerprint.json`（slx/sldd/mexw64/dll/mat） |
| 运行前后 Git 状态 | `git_state_before.json` / `git_state_after.json` |
| 生成文件三分类 | `generated_assets.json`：`commit_candidate` / `regenerated_by_run` / `excluded_from_source` 等 |
| 未提交产物不冒充源码 | `committed_sha256` 只取 `git ls-tree HEAD`；`sha256` 取磁盘；`clean=false` 时列出脏文件 |
| 失败/提前退出可归档 | `tests/verify_archive_failure_path.ps1` F-01…F-05 全 PASS；manifest `archive_completeness` |

新增测试：`tests/verify_archive_reliability.m`（A-01…A-06，已接入组件门，本轮 PASS）、`tests/verify_archive_failure_path.ps1`（F-01…F-05）。

### 2.2 阶段二：M7 执行器事务（P0，Issue #13）——部分完成

| 项目 | 结果 |
|---|---|
| `permit_lifecycle` | **PASS**（Flight 主机套件 38 checks） |
| `frame_apply_500us` | **PASS**（同上） |
| `ground_stop_transaction` | `NOT_RUN`，`ground_stop_evidence = NOT_IMPLEMENTED_IN_FIRMWARE` |

Ground Stop 不是测试缺口：`middleware/`、`applications/` 检索 `GroundStop`/`ZERO_TARGET`/`certificate` 零命中，地面路径只有 `fms_permit_ground_disarm()`（撤销 Permit 后直接 DISARMED）。按约束未在 Matalab 侧伪造。

### 2.3 阶段三：M6 控制器（P1，Issue #12）——部分完成

| 项目 | 结果 |
|---|---|
| `qp_assembly_in_model` | **PASS**（13 checks：`n=15`、`m=190`、P nnz 45、A nnz 702） |
| `strict_validation_in_model` | **PASS**（`prim_res=7.45e-9`、`dual_res=7.46e-4`） |
| `complete_M6_time_context_guard` | **PASS**（11 checks） |
| `closed_loop_rate_step` | **PASS**（settle 0.460 s / 超调 1.4% / 保持误差 0.0062 rad/s） |
| MPC job 统计 | **FAIL**：488 job、20 solved（4.1%）、覆盖 1.5% |

容差实验记录：把三处绝对门限改成随尺度缩放后成功率升到 91.8%，但同一命令带下 MIL 起飞失败（`did not reach the required 1.8 m minimum takeoff altitude`），已整条回退。这说明 1e-3 门限承担了实际行为约束，放宽需要控制层面的论证。

### 2.4 阶段四：P-10b（P1，Issue #14）——部分完成

| 项目 | 结果 |
|---|---|
| 固件时统进入 Host MIL | 完成（`systime.c` 链接进 DLL，Host 时钟改 0 起点对齐） |
| PPS capture 注入 | 26 s MIL：26 次提交、0 拒绝 |
| UM982 RECTIMEA 解析 | 26 帧解码（真实 `unicore_ascii` + 录制句子） |
| GNSS 时间配对 | 26 次 `time_submit_gnss_time` 成功 |
| `utc_mapping_verified` | `NOT_RUN` |
| `holdover_recovery_verified` | `NOT_RUN` |

## 3. 实际执行的测试

| 套件 | 结果 |
|---|---|
| Flight `tests/actuation`（M7） | 38 checks / 0 failures |
| Flight `tests/control`（M6 组装） | 13 checks / 0 failures |
| Flight `tests/control`（M6 上下文守卫） | 11 checks / 0 failures |
| Flight `tests/simulation` SIL 场景 | 4147 checks / 0 failures |
| Matalab 归档可靠性 | A-01…A-06 PASS；F-01…F-05 PASS |
| Matalab 速率阶跃 | PASS（0.460 s / 1.4% / 0.0062） |
| Matalab P-10b 注入 | PASS（26/26/26，0 拒绝） |
| Matalab 完整回归 | 15 PASS / 1 PARTIAL / 1 FAIL |

## 4. 修改文件清单

**Flight**（分支 `test/fmat-0012-m6-controller`）

- `middleware/model/control/outer_loop/quad_x4/mpc_solver/mpc.c` — MPC 运行统计与计数
- `middleware/model/control/inner_loop/quad_x4/attitude_rate_control/controller_internal.h` — `MpcRunStats` 与接口
- `middleware/model/control/control_interface.h` — `mpc_note_worker` 声明
- `applications/tasks/mpc/task_mpc.c` — worker tick 上报
- `tests/actuation/test_m7_main.c`、`tests/actuation/run_host_tests.ps1`（新增）
- `tests/control/test_m6_main.c`、`tests/control/test_m6_guard_main.c`、`tests/control/run_host_tests.ps1`（新增）
- `tests/simulation/sil_flight.c` — 时统桩编译开关
- `.gitignore` — 忽略 `work/`

**Flight_Matalab**（分支 `optimize/sil-physical-parameter-alignment`）

- `tools/fingerprint_sources.py`（重写）、`tools/fingerprint_artifacts.py`（新增）、`tools/git_state.py`（新增）、`tools/flight_acceptance_snapshot.m`（新增）
- `tools/archive_validation_run.ps1` — manifest schema 1.1
- `tools/run_component_checks.m` — 快照、`p10b`、`m6_jobs` 门
- `tests/verify_archive_reliability.m`、`tests/verify_archive_failure_path.ps1`（新增）
- `tests/verify_actuation_components.m`、`tests/verify_osqp_gate.m`、`tests/verify_rate_pid_transaction.m`、`tests/verify_m6_jobs.m`、`tests/verify_m6_rate_step.m`、`tests/verify_p10b_pps_rectime.m`（新增）、`tests/verify_flight_entries.m`
- `adapters/flight_runtime/fmt_flight_runtime.c` — MPC/P-10b 统计与注入
- `spec/validation/` 四份文档、`config/flight_baseline.json`

## 5. Issue 状态

| Issue | 状态 | 说明 |
|---|---|---|
| #12（M6） | open | 组装/严格校验/上下文守卫/速率阶跃 PASS；MPC 成功率 4.1% 未达标 |
| #13（M7） | open | permit 与帧应用 PASS；Ground Stop 为固件功能缺口 |
| #14（P-10b） | open | 时统接入与 PPS/RECTIMEA 注入 PASS；UTC 纪律与失锁恢复未验证 |

## 6. 下一阶段任务（按优先级）

1. **MPC 成功率（P0）**：查清"为什么 96% 的求解被 1e-3 门限拒绝、被放行的解又控制不好"。需要判断是 QP 病态（权重/边界尺度）、还是 MPC 与内环/分配器在边界条件下不稳。在结论出来前不要调门限。
2. **Ground Stop 实现（P0）**：Flight 侧新增 `GroundStopCertificate` 契约、`actuator_guard_ground_stop()`、`ZERO_TARGET_APPLIED` 回执与 DISARMED 后非零推力锁死；完成后 #13 的第三个 NOT_RUN 才能转 PASS。
3. **P-10b 剩余两项（P1）**：UTC 授时纪律（`time_get_status` 的 UTC 有效位随 RECTIMEA 更新）与失锁/恢复（PPS 丢失后 holdover、恢复后重新锁定），各需独立夹具。
4. **覆盖率口径（P2）**：`time_weighted_coverage` 的分母是否排除非轨迹模式时段，需要按 Issue #12 口径确认。
5. **已知固件缺陷（P2）**：`controller.c:214` 的 `finite_array(n->core.position_ned_m, 6)` 读取了 3 元素数组之后的 3 个 float（越界读），建议单独立项。

## 7. 边界声明

- 本轮全部结果来自 PC MATLAB/Simulink + Windows Host SIL，**不构成 H723 实机、PIL/HIL 或实飞验证**；
- 未实测项一律保持 `NOT_RUN`，未以"应该可以"替代证据；
- 唯一一次尝试放宽门限导致 MIL 起飞失败，已回退并在 Issue #12 中留档，未作为改进计入结果。
