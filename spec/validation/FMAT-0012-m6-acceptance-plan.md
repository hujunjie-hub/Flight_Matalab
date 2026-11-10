# FMAT-0012（M6 控制器）验收审查与实现计划

- 对应 Issue：Flight_Matalab#12（`[FMAT-0012][S1][M6]`）
- 分支：`optimize/sil-physical-parameter-alignment`
- 状态：IN_PROGRESS（审查完成，测试待实现）

## 1. 审查结论：实现大部分已存在，缺的是"在模型路径内"的证据

`middleware/model/control/outer_loop/quad_x4/mpc_solver/mpc.c` 的 `mpc_solve()` 已经完成了 Issue #12 要求的多数动作，只是没有测试驱动它并留下数字：

| Issue #12 要求 | 真实实现位置 | 现状 |
|---|---|---|
| QP 组装（15 变量 / 190 约束） | `mpc_solve` L92-177：H 用 `qp_p_ptr/qp_p_row`（45 nnz），q 逐列累加，A 用 `qp_a_ptr/qp_a_row`（702 nnz） | 已实现，未被模型内测试覆盖 |
| 求解器状态分派 | L182-203：`SOLVED` / `SOLVED_INACCURATE` / `MAX_ITER`→`NOT_READY` / `PRIMAL|DUAL_INFEASIBLE`→`OUT_OF_RANGE` / 其它→`NUMERIC_ERROR` | 已实现 |
| 独立残差检查 | L204-207：`prim_res`/`dual_res` 必须有限且 ≤1e-3 | 已实现 |
| 独立约束违反检查 | L208-225：用 `A·x` 重算 190 条约束，允许 1e-3 越界；再检查 5 步推力球 `mass·|a| ≤ max_total_thrust_n + 1e-3` | 已实现 |
| 候选解有限性 | L212：`finite_array(x,15)` | 已实现 |
| 控制时刻陈旧 | L248-251：`now - control_time_us + uncertainty > 5000` → `STALE_DATA` | 已实现 |
| 未来时刻 | L244：`now < evaluation_time_us` → `STALE_DATA` | 已实现 |
| 求解节流 | L252：两次求解间隔 <20 ms → `NOT_READY` | 已实现 |
| 上下文一致性 | `same_context()` L50-67：boot/time epoch、nav/origin、reference/authority/directive/envelope/model epoch 与 `safety_envelope_id` 全部相等 | 已实现 |
| 输入合法性 | L78-80 模型域、L154-156 NaN 导航位置、L175-177 边界有限且 `lower ≤ upper` | 已实现 |

因此 `short strict_validation_in_model` 与 `qp_assembly_in_model` 不是"没实现"，而是**没有在模型路径内被驱动过**。现有 `verify_osqp_gate.m` 用的是合成 P/q（真实稀疏结构，但自己拼数据），只证明 MEX 求解器本身正确。

## 2. 要补的测试

### 2.1 `tests/control/test_m6_main.c`（Flight 侧，复用真实 `mpc_solve`）

夹具：`ControllerInput`（`port_types.h`）+ `ProductControllerConfigPayload` + `ControlModelView` + `ProductSafetyEnvelopePayload`，`control_time_us` 与 `clock_read` 桩同步推进。

| 编号 | 用例 | 断言 |
|---|---|---|
| M6-01 | 合法轨迹参考 + 静止 nav | `STATUS_OK`，`solver_status=SOLVED`，输出 3 维加速度有限 |
| M6-02 | QP 维度合同 | `quad_solver` 工作区 15 变量 / 190 约束 / 45 P nnz / 702 A nnz，与头文件一致 |
| M6-03 | 独立残差 | 用 `A`、`lower`、`upper` 重算 `A·x`，违反量 ≤1e-3；推力球 ≤`max_total_thrust_n+1e-3` |
| M6-04 | 候选解严格性 | 人为把 `prim_res` 调到 `SOLVED_INACCURATE` 会返回 `STATUS_OK` 但 `solver_status=SOLVED_INACCURATE`（不得被当作严格解） |
| M6-05 | `MAX_ITER` | 设 `osqp_set_max_iter(1)` → `STATUS_NOT_READY`、`solver_status=MAX_ITER` |
| M6-06 | 原/对偶不可行 | 把 `lower > upper` 注入 → `STATUS_OUT_OF_RANGE` |
| M6-07 | NaN 导航 | `position_ned_m[0]=NaN` → `STATUS_INVALID_ARGUMENT` |
| M6-08 | 参考过期 | `control_sample_reference` 失败 → `STATUS_STALE_DATA` |
| M6-09 | 上下文错代 | 改 `reference_epoch` / `state_epoch` / `safety_envelope_id` → `STALE_DATA` |
| M6-10 | 控制时刻陈旧 | `now - control_time_us > 5000` → `STALE_DATA` |
| M6-11 | 未来 evaluation | `evaluation_time_us > now` → `STALE_DATA` |
| M6-12 | 求解节流 | 20 ms 内二次调用 → `NOT_READY` |

构建：`tests/control/run_host_tests.ps1`，链接 `mpc.c` + `middleware/model/control/outer_loop/quad_x4/mpc_solver/osqp/generated/src/*.c`。

### 2.2 模型内覆盖率统计（`qp_assembly_in_model` / job 统计）

`FMT_FlightCore` 一轮 26 s MIL 有 1300 次 MPC 更新。需要在运行时把每次求解的 `solver_status` 与调用时刻记入诊断，再由 MATLAB 侧统计：

- 合格 job 数（`solver_status ∈ {SOLVED, SOLVED_INACCURATE}` 且通过严格校验）≥100；
- 成功率 = 合格 / 总求解 ≥99%；
- 时间加权覆盖率 = 有效 MPC 周期时长 / 闭环时长 ≥90%（PD fallback 空窗必须计入分母，不得剔除）。

现状：`flight_entries.json` 只有 `mpc_updates` 计数，没有状态分布。需要在 Flight 侧给 M6 增加一个只读诊断计数器（按 status 分桶 + 累计空窗时长），由 runtime 输出，MATLAB 记录到 `m6_report.json`。

### 2.3 0.5 rad/s 速率阶跃（`closed_loop_rate_step`）

独立 MIL fixture：真值姿态/角速度注入，速率指令 0.5 rad/s 阶跃，指标 ±5% 内 ≤1.5 s、超调 ≤30%、保持 2 s，禁用地面接触与执行器饱和干扰。可直接复用 `FMT_QuadPlant` + `FMT_RatePIDTransaction` 组合成开环受控夹具，不依赖 `FMT_FlightCore` 的完整生命周期。

## 3. 为什么本轮没有直接给 PASS

`strict_validation_in_model` 与 `qp_assembly_in_model` 只有在 2.1 的夹具跑通后才允许置 PASS；`complete_M6_time_context_guard` 需要 2.1 的 M6-09…M6-12 全部通过；`closed_loop_rate_step` 需要 2.3 的独立夹具；job 统计需要 2.2 的 Flight 侧诊断计数器。在这些证据产生之前，四个字段继续保持 `NOT_RUN`。
