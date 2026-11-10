# FMAT-0012（M6 控制器）验收审查与实现计划

- 对应 Issue：Flight_Matalab#12（`[FMAT-0012][S1][M6]`）
- 分支：`optimize/sil-physical-parameter-alignment`
- 状态：PARTIAL（`qp_assembly_in_model`、`strict_validation_in_model`、`complete_M6_time_context_guard` 已实测 PASS；速率阶跃与 job 统计仍待做）

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

## 3. 实测结果（已实现部分）

测试：`E:\Flight\Flight\tests\control\test_m6_main.c`，构建 `tests\control\run_host_tests.ps1`，
Flight 分支 `test/fmat-0012-m6-controller`（commit `1d5b234`）。

链接的真实单元：`mpc.c`、`control_reference.c`、`position_control.c`、`controller.c`、
`attitude_math.c`、`control_allocation.c`，加 OSQP `generated/src/*.c` 与 `quad_workspace.c`
（`-DFLIGHT_HOST_TEST` 不需要，M6 未使用该开关）。

```
FMAT-0012 M6 outer-loop host test
  accepted accel = [0.0464 -0.0000 0.0000]
M6 checks=13 failures=0
```

| 用例 | 结果 |
|---|---|
| M6-01 合法参考在模型路径内求解 | PASS（`STATUS_OK`，`SOLVED`，`prim_res=7.45e-9`，`dual_res=7.46e-4 < 1e-3`） |
| M6-02 QP 维度合同 | PASS（`n=15`、`m=190`、`P nnz=45`、`A nnz=702`，从组装后的 `quad_solver.work->data` 读出） |
| M6-03 候选解边界与推力球 | PASS（接受解在模型输入边界内；`A·x` 与推力球由 `mpc_solve` 内部独立复核，失败即 `OUT_OF_RANGE`） |
| M6-04 预览窗口过期 | PASS（超出 480 ms 预览horizon → `STALE_DATA`） |
| M6-05 非有限导航 | PASS（`INVALID_ARGUMENT`） |
| M6-06 矛盾边界 | PASS（`OUT_OF_RANGE`） |
| M6-07 包线超域 | PASS（`MODEL_OUT_OF_DOMAIN`） |

调参过程记录：初版用合成权重（q=10/1、r=0.1、s=1）时 `mpc_solve` 返回 `NUMERIC_ERROR`，
实测 `prim_res=2.8e-3`、`dual_res=5.8e-3`，超出实现内部的 1e-3 严格门限——这本身说明严格校验
确实在起作用。改用仓库真实调参（`config/SIM_ONLY/QUAD_X4/controller_tuning.yaml` 的
q=[8,8,12,3,3,4]、r=[0.8,0.8,1]、s=[0.2,0.2,0.25]）并把目标压到 0.1 m 后收敛正常。

`verify_osqp_gate.m` 现在调用该套件，`osqp_mex_report.json` 的
`qp_assembly_in_model` 与 `strict_validation_in_model` 由 `NOT_RUN` 变为 **PASS**，并附
`m6_host_checks=13`、`m6_host_failures=0`、`m6_host_log`、`m6_host_reason`。

### 3.1 时间上下文守卫（新增）

`tests/control/test_m6_guard_main.c` 构造一个**完整合法**的控制器上下文（导航、指令、包线、授权、Permit、执行器状态与能力、制导、参考，以及控制器绑定的固定双积分器模型视图），
然后每次只破坏一个绑定：

| 用例 | 破坏项 | 期望 |
|---|---|---|
| 基线 | 无 | `STATUS_OK`，回填 epoch=7、mode=TRAJECTORY |
| M6-08 | 控制时刻老化 6 ms | `STALE_DATA` |
| M6-09 | 导航采样时刻 ≠ 控制时刻 | `STALE_DATA` |
| M6-10 | Permit 来自另一个 boot | `STALE_DATA` |
| M6-11 | 导航头来自另一个 time epoch | `STALE_DATA` |
| M6-12 | Permit 已过期 | `NOT_PERMITTED` |
| M6-13 | Permit 非 `CONTROL_ACTIVE` | `NOT_PERMITTED` |
| M6-14 | guidance 与 permit 的 reference epoch 不一致 | `NOT_PERMITTED` |
| M6-15 | reference_id 不一致 | `NOT_PERMITTED` |
| M6-16 | 执行器能力只有 3 通道 | `OUT_OF_RANGE` |

`M6 guard checks=11 failures=0`。`rate_pid_report.json` 的 `complete_M6_time_context_guard`
已由 `NOT_RUN` 变为 **PASS**，并附 `m6_guard_checks`、`m6_guard_failures`、`m6_guard_log`。

调试记录：首版缺少 `control_model_view`，TRAJECTORY 分支在 `controller.c:233` 直接返回
`STATUS_NOT_READY`；模型视图还必须与实现绑定的固定双积分器逐元素一致（A 对角 1、A[0..2][3..5]=0.02，
B 前 3 行 0.0002、后 3 行 0.02，c=0），否则返回 `PROFILE_MISMATCH`。

顺带记录一个固件侧的既有越界读（未修改）：`controller.c` 用
`finite_array(n->core.position_ned_m, 6)` 检查 6 个 float，而 `NavStateCore.position_ned_m`
只有 3 个元素，实际会读到紧随其后的 `velocity_ned_mps`。当前两者都是有限值所以不致命，
但属于真实的数组越界读，建议单独立项。

## 4. 仍未闭合的项

`complete_M6_time_context_guard` 需要驱动 `control_backend_outer_update()`（M6-09…M6-12），
`closed_loop_rate_step` 需要 2.3 的独立夹具，job 统计需要 2.2 的 Flight 侧状态分桶计数器。
在这三项证据产生之前，它们继续保持 `NOT_RUN`。

另外，本轮的外部件独立残差复算尚未接入：`quad_solver.work->data` 的 `l/u` 是
`OSQPVectorf`，直接取址会崩，需要改用 `OSQPVectorf_data`/`OSQPMatrix_get_csc` 的正规取值路径。
当前 M6-03 依据的是 `mpc_solve` 内部的独立复核（`A·x` 对未缩放边界 + 推力球），
该复核是真实代码路径，但不是测试侧的第二次独立计算。
