# FMAT-0013（M7 执行器事务）验收计划与实现审查

- 对应 Issue：Flight_Matalab#13（`[FMAT-0013][S1][M7]`）
- 分支：`optimize/sil-physical-parameter-alignment`
- 状态：**PASS**（permit_lifecycle、frame_apply_500us、ground_stop_transaction 均已实测 PASS；有效范围与未覆盖项见第 5.4 节）

## 1. 审查范围（真实实现，不新建模拟逻辑）

| 环节 | 真实实现 | 位置 |
|---|---|---|
| Permit 签发/续租/撤销/水位 | `fms_permit_tick` / `fms_permit_revoke` / `fms_permit_fill` | `middleware/model/fms/quad_x4/flight_safety/actuation_permit.c` |
| Permit 消费侧闸门 | `actuator_update_permit` / `bound` / `demand_valid` | `middleware/actuator/output_guard/actuator_guard.c` |
| 500 μs 帧边界与应用 | `actuator_guard_frame_boundary` | 同上 |
| 提交回执 | `ActuatorCommitReceipt`（`commit_time_us`、`estimated_apply_time_us`、`receipt_expires_at_us`） | 同上 |
| 量化/校验和 | `FMT_M7_FrameQuantizer`（MATLAB 侧已 PASS：code0/合法范围、slew、逆映射、DShot checksum） | `tests/verify_actuation_components.m` |

M7 的真实语义是"**提交 ≠ 应用**"：

- `actuator_apply()` 只把最新 demand 暂存（`a.latest`），注释明确 *"Publishing a demand is deliberately not a commit receipt."*；
- 真正的物理应用发生在 `actuator_guard_frame_boundary(now)`，以 400 Hz（2.5 ms）为最小间隔（`now - last_frame < 2500` → `STATUS_DEADLINE_MISSED`）；
- 应用量受 `max_slew_nps[m] × elapsed` 限制，码值由推力曲线插值得到，回执记录 `estimated_apply_time_us`。

### 1.1 消费侧已实现的防护（可直接验收）

| 规则 | 实现位置 | 期望行为 |
|---|---|---|
| 来源/时钟一致性 | `actuator_update_permit` L98-100 | 非 `SOURCE_M4`、boot/time epoch 不符、`permit_epoch==0` → `STATUS_NOT_PERMITTED` |
| 旧代重放 | L102-104 | `permit_epoch` 落后于 watermark 且非 newer → `STATUS_STALE_DATA` |
| 撤销后不可复活 | L106-107 | 同代已发布 `PERMIT_FLAG_REVOKED` 时，非撤销帧不得重新建立 Permit |
| 同代绑定不可漂移 | L108-111 | authority/directive/state/reference epoch 或 policy 变化 → `STATUS_NOT_PERMITTED` |
| 同代乱序 | L112-116 | sequence 或 publish 时间回退 → `STATUS_STALE_DATA` |
| 过期 | `bound` L36-42 | `permit_expires_at_us <= now` → 不 bound，`inhibit()` |
| 重复帧 | `actuator_guard_frame_boundary` L150 | 2.5 ms 内再次调用 → `STATUS_DEADLINE_MISSED`，不重复应用 |
| 过期 demand | L155/L178 | `now - last_demand > 5000` → `SAFE_ACTION` |
| 单调 demand 序列 | `actuator_apply` L139 | 非递增 `control_sequence` → `STATUS_STALE_DATA` |

## 2. 关键发现：Ground Stop 在固件中不存在

Issue #13 第 4 条要求"只允许 LANDED/DISARMING 下的有效 `GroundStopCertificate`、≤100 N/s 降推力、最终 stop code 0、零目标应用 ≤105.5 ms、`ZERO_TARGET_APPLIED` 之后才允许 DISARMED"。

对 `middleware/`、`applications/` 全量检索 `GroundStop`、`ground_stop`、`ZERO_TARGET`、`ZERO_TARGET_APPLIED`、`certificate`：

- **零命中**（唯一 `certificate` 命中是 OSQP 的不可行性证书，与本主题无关）；
- `actuation_permit.c` 只在地面 disarm 路径出现注释 *"no motion, controlled ground stop"*，其实现是 `fms_permit_ground_disarm()`——撤销 Permit、清 authority、置 `DISARMED`、记 `DECISION_FORCE_SAFE_ACTION`，**没有**降推力斜坡、没有 stop code 0、没有证书对象、没有 `ZERO_TARGET_APPLIED` 确认。

因此第 4 条不是"测试缺口"，而是**功能缺口**。按任务约束（"先审查 M7 真实实现，不要另建一套模拟执行器逻辑"、"未实测项保持 NOT_RUN"），本轮不会在 Flight_Matalab 侧伪造 Ground Stop 实现，`actuation_report.json` 的 `ground_stop_transaction` 当时保持 `NOT_RUN`，并在 Issue #13 中登记为需要 Flight 侧新增的能力（**该缺口已于 2026-11-11 补齐，见第 5 节**）。

建议的 Flight 侧最小实现（供后续 Issue 立项）：

1. `GroundStopCertificate` 契约消息：`source=M4`、`lifecycle ∈ {LANDED, DISARMING}`、`ground_truth_valid`、`boot/time epoch`、`expires_at_us`；
2. `actuator_guard_ground_stop(certificate)`：仅当生命周期与接地事实同时成立时进入 `GROUND_STOP`，按 `max_decel_nps ≤ 100 N/s` 线性降推力，末值写 stop code 0；
3. `ZERO_TARGET_APPLIED` 回执后才允许 `ACTUATOR_GUARD_DISARMED`；DISARMED 后任何非零管理推力 → `FAULT_LATCHED`。

## 3. 本轮要交付的测试（`tests/actuation/test_m7_main.c`）

驱动真实 `actuator_guard.c`，用 host 端 `clock_read` 桩 + 记录型 `commit` 驱动，覆盖：

| 编号 | 用例 | 断言 |
|---|---|---|
| M7-01 | 合法 Permit + demand 在帧边界提交 | `STATUS_OK`，commit 回调被调用一次 |
| M7-02 | `actuator_apply` 不产生回执 | 提交前后 `commit` 调用次数不变 |
| M7-03 | 500 μs 内重复帧 | `STATUS_DEADLINE_MISSED`，commit 次数不增 |
| M7-04 | 2.5 ms 后的下一帧 | 应用，且 slew 受 `max_slew_nps × elapsed` 限制 |
| M7-05 | 撤销后代号重放 | `STATUS_STALE_DATA`（旧 token 不可复活） |
| M7-06 | 同代撤销帧后再签同代 | `STATUS_NOT_PERMITTED` |
| M7-07 | 同代乱序（sequence 回退） | `STATUS_STALE_DATA` |
| M7-08 | boot_id / time_epoch 不符 | `STATUS_NOT_PERMITTED` |
| M7-09 | Permit 过期 | 不 bound，`inhibit` 被调用 |
| M7-10 | demand 超过 5 ms | `ACTUATOR_GUARD_SAFE_ACTION` |
| M7-11 | 回执时间语义 | `estimated_apply_time_us >= commit_time_us`，`receipt_expires_at_us = commit + 5000` |

构建：`tests/actuation/run_host_tests.ps1`（照 `tests/health/run_host_tests.ps1` 的形式），加 `-DFLIGHT_HOST_TEST` 以启用 `SIM_CONTROLLED_STOP` 策略；结果落 `build/validation/m7/actuation_host_summary.json`。

MATLAB 侧：`verify_actuation_components.m` 调用该脚本，把 `permit_lifecycle` 与 `frame_apply_500us` 设为 PASS（仅在实测通过时），`ground_stop_transaction` 当时保持 `NOT_RUN` 并在报告里附 `ground_stop_evidence = "NOT_IMPLEMENTED_IN_FIRMWARE"`（现已改为真实固件证据，见第 5 节）。

## 4. 实测结果（已实现）

测试文件：`E:\Flight\Flight\tests\actuation\test_m7_main.c`，构建脚本 `tests\actuation\run_host_tests.ps1`，
Flight 分支 `test/fmat-0013-m7-actuation`（commit `5eb9e4e`），Draft PR hujunjie-hub/Flight#4。

```
FMAT-0013 M7 actuator guard host test
M7-01..04 frame boundary and apply separation
M7-05..07 permit watermark, revocation and ordering
M7-08..10 boot/time epoch binding, permit expiry, stale demand
M7 checks=38 failures=0
```

| 项 | 结果 |
|---|---|
| `permit_lifecycle` | **PASS**（38 checks / 0 failures） |
| `frame_apply_500us` | **PASS** |
| `ground_stop_transaction` | **PASS**（2026-11-11 实现，见第 5 节；本节表格为当时的实现状态） |

**反向验证**：把 `actuator_update_permit` 里的水位判据改为恒假后重建，恰好 M7-05 与 M7-06 两条失败（2/38），其余 36 条仍通过——说明用例咬住的是实现规则，不是夹具。还原后重新 38/38。

MATLAB 集成：`verify_actuation_components.m` 通过 `run_m7_host_suite` 调用该脚本并解析
`build/validation/m7/actuation_host_summary.json`；`actuation_report.json` 新增
`m7_host_checks`、`m7_host_failures`、`m7_host_log`、`m7_host_reason`、`ground_stop_evidence` 字段。

## 5. Ground Stop 已实现（2026-11-11）

第 2 节记录的功能缺口已补齐，实现位于真实固件路径 `middleware/actuator/output_guard/actuator_guard.c`，没有在 MATLAB 侧模拟。

### 5.1 契约

| 项 | 定义 |
|---|---|
| 消息 | `MSG_GROUND_STOP_CERTIFICATE` (56)，`GroundStopCertificate` |
| stop code | 仅 `ACTUATOR_GROUND_STOP_CODE_ZERO`（0），其他一律 `STATUS_OUT_OF_RANGE` |
| 生命周期 | `ACTUATOR_GROUND_STOP_LIFECYCLE_LANDED` / `_DISARMING`；取值刻意放在 `0x1001/0x1002`，避免用 `LandedState` 常量误判通过 |
| 降推力速率 | `> 0` 且 `<= ACTUATOR_GROUND_STOP_MAX_RAMP_NPS`（100 N/s） |
| 应用时间预算 | `ACTUATOR_GROUND_STOP_MAX_APPLY_US`（105,500 µs）= 满推力降速时间 + 1 帧 2.5 ms + 驱动 3 ms |
| 回执 | `ACTUATOR_RECEIPT_ZERO_TARGET_APPLIED`（4） |

证书不是 `ActuatorDemand`：它没有 control sequence，也不需要有效 Permit —— 停止不能依赖一个已被撤销的许可。

### 5.2 事务语义

1. `actuator_guard_ground_stop()` 只做受理：校验头部时钟/来源 M4/有效期、stop code、速率、生命周期，并按配置的最大推力预算判断能否在 105.5 ms 内归零；不满足则拒绝，而不是稍后超时。
2. 之后每个 400 Hz 帧边界按 `ramp_nps × Δt` 把四路推力单调压到 0，走与需求路径**同一** `thrust_to_code()` 映射，因此不会跳变。
3. 恰好到 0 的那一帧写入 `ZERO_TARGET_APPLIED` 回执，**然后**才进入 `ACTUATOR_GUARD_DISARMED` 并 `inhibit()`。
4. 完成后置 latch：`actuator_apply()` 与帧边界一律拒绝，输出保持零推力码，直到下一次 `actuator_init()`。
5. 超过预算仍未归零时在回执 `limit_flags` 置 `ACTUATOR_GROUND_STOP_OVERRUN_FLAG`（不掩盖超时）。

### 5.3 实测（Flight `tests/actuation`，226 checks）

| 用例 | 结果 |
|---|---|
| M7-11 畸形证书 | PASS（stop code 1 / 101 N/s / IN_AIR / 来源 M6 / 过期证书全部拒绝） |
| M7-12 撤销后仍可停止 | PASS |
| M7-13 速率与单调性 | PASS（单帧最大 0.25 N = 100 N/s，从不回升） |
| M7-14 零目标回执 | PASS（四路均恰好 0 N，`ZERO_TARGET_APPLIED`） |
| M7-15 应用时间 | PASS（**40 帧 / 100,000 µs 归零，受理到应用 100,500 µs ≤ 105,500 µs**） |
| M7-16 DISARMED 与锁死 | PASS（仅在零回执后 DISARMED；之后的 demand 与帧均不产生提交，输出为零推力码） |

`actuation_host_summary.json` 现在输出 `ground_stop_transaction=PASS`、`ground_stop_evidence=FIRMWARE_GROUND_STOP_CERTIFICATE`、`ground_stop_max_apply_us=105500`、`ground_stop_max_ramp_nps=100` 和一行实测摘要。

### 5.4 未覆盖

- FMS 侧签发证书的触发逻辑（本 Issue 只覆盖执行器侧消费与确认）；
- 真实 ESC/DShot 物理推力响应、H723 实机时序与 PIL/HIL（Host SIL 只证明命令与回执时序）。
