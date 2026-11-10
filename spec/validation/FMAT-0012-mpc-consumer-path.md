# FMAT-0012 附记：MPC 快照的消费路径

- 记录时间：第 30 轮
- 目的：为"MPC 合法解却有害"这一结论提供精确的下阶段入口
- 状态：路径已确认，根因未定

## 1. 唯一消费者

`middleware/model/control/outer_loop/quad_x4/position_tracking/position_control.c:61` 的 `position_control_track()`：

```c
mpc_read(&cached_mpc);                                   /* L74 */
backup = !(cached_mpc.expires_at_us > in->evaluation_time_us &&
           same_clock(&cached_mpc.header, &in->navigation->header) &&
           cached_mpc.state_epoch   == in->navigation->state_epoch &&
           cached_mpc.origin_id     == in->navigation->origin_id &&
           cached_mpc.reference_epoch == epoch &&
           cached_mpc.authority_epoch == in->authority_status->authority_epoch &&
           cached_mpc.directive_epoch == in->directive->directive_epoch &&
           cached_mpc.envelope_epoch  == in->safety_envelope->envelope_epoch &&
           cached_mpc.model_epoch     == in->control_model_view->model_epoch &&
           cached_mpc.safety_envelope_id == in->safety_envelope->safety_envelope_id);  /* L87-98 */
for (i = 0; i < 3; ++i)
  if (fabsf(nav.position - cached_mpc.position[i]) > 0.5f ||
      fabsf(nav.velocity - cached_mpc.velocity[i]) > 0.5f)
    backup = 1;                                          /* L100-105 */
requested[i] = backup ? ref.acc + kp*(ref.pos - nav.pos) + kd*(ref.vel - nav.vel)
                      : cached_mpc.acceleration[i];      /* L106-114 */
```

即：快照在**有效期、时钟、六类 epoch、包线 id 全部一致**且**导航相对快照种子偏离 ≤0.5 m / 0.5 m/s** 时，MPC 的 `acceleration` 被直接当作期望加速度；否则走 PD 回退。

## 2. 与实测现象的一致性

| 实验 | 求解被接受 | 结果 |
|---|---|---|
| 基线 | 20 / 488（4.1%） | 通过，2.098 m |
| 放宽候选门限 | 449 / 489（91.8%） | 起飞失败 |
| 收紧求解器容差（门限不变） | 468 / 489（95.7%） | 起飞失败 |

基线那 20 个解集中在悬停附近（偏离小、加速度小），MPC 实质不介入；一旦接受数上升，加速/爬升段的解就进入姿态环。消费路径与现象一致。

## 3. 待确认的语义

`mpc_solve()` 末尾 `memcpy(out->acceleration, x, 3*sizeof(float))` 取首个控制移动的前三个分量。从上下界 `lower/upper[135+index] = ±0.02*slew + (k==0 ? prev[i] : 0)` 判断，变量应为**绝对加速度**，`prev` 只约束首步斜率。

若该判断成立，"合法解却有害"只剩四种解释：

1. `response()` 的 20 ms 预测与实际闭环在量纲/符号上不一致（尤其 `move==4` 的常值段与 `velocity` 分支）；
2. 代价权重 `q=[8,8,12,3,3,4]`、`r=[0.8,0.8,1]`、`s=[0.2,0.2,0.25]` 与实际动力学、`actuation_preview_delay_s=0.002` 的时序不匹配；
3. `state_min/max = ±100 m` 相对约 1 m 的实际状态尺度失衡，约束活跃时给出偏置解；
4. 首步对应 `control_time + preview_delay`，而消费侧在 `evaluation_time` 直接使用，2 ms 相位差与 1 kHz 内环不匹配。

## 4. 建议做法

不要再用"提高成功率"来验证（已被三次实验否证）。建议在 `position_control_track()` 增加诊断通道，同时记录：

- `backup` 标志；
- `cached_mpc.acceleration`；
- PD 回退给出的 `requested`；

一次 MIL 即可看出爬升段两者差异的方向与量级，比继续猜代价参数高效。该诊断只在 Host 侧开启，不改变固件行为。

## 4.1 第 31 轮的实测（Host 只读诊断）

在 `position_control_track()` 增加 Host 专用诊断（`#ifdef FLIGHT_HOST_TEST`，只读、不改行为），26 s MIL 得到：

```
outer_samples   = 9760      /* 每个 1 kHz 内环周期采样一次 */
outer_mpc_used  = 80        /* 真正采用 MPC 加速度的周期数 */
outer_max_diff  = 0.1597    /* MPC 与 PD 回退值之差的最大值，m/s^2 */
outer_max_mpc   = 0.1609    /* MPC 加速度峰值，m/s^2 */
outer_min_life_us = outer_max_life_us = 8000   /* 快照有效期 */
```

三点结论：

1. **MPC 在这 9.76 s 里只被采用 80 个 1 kHz 周期（约 80 ms）**，参与度极低；
2. 被采用时 MPC 与 PD 的差异最大仅 **0.16 m/s²**（约 1.6% g），幅度很小；
3. 快照有效期实测恒为 **8 ms**，而外环周期是 20 ms——即使求解成功，也只有约 40% 的时间窗可用。

第 3 点若成立，将直接解释"MPC 参与度低"；但也可能是我的测量口径问题：寿命用 `expires_at_us - header.timestamp_sample_us` 计算，而 `timestamp_sample_us` 的语义（导航采样时刻 vs 求解时刻）尚未核实。**该数字在核实前不应作为结论引用。**

诊断代码已回退（Host 与固件均恢复原状，MIL 短跑 `MIL_OK`），避免把未核实的口径留在固件里。若下一阶段继续，建议先把 `expires_at_us` 的 min 链逐项打印出来（本轮的索引记录返回 0，即 `start+20000`，与 8 ms 的实测矛盾，说明口径还需查清）。

## 4.2 第 36 轮：快照到期被执行器消息掐住（已核实）

在消费侧记录被采用那一刻的三个时间戳（Host 只读，26 s MIL）：

```json
{ "used_samples": 80,
  "expires_us": 13905000, "sample_us": 13897000, "eval_us": 13904000,
  "life_us": 8000, "expires_minus_eval_us": 1000 }
```

- `sample_us` 是导航采样时刻，`eval_us` 是消费时刻，两者相差 **7 ms**；
- 快照的 `expires_at_us = sample + 8000`，因此被消费时只剩 **1 ms**；
- 外环周期是 20 ms，1 kHz 内环每 1 ms 采一次，于是每次成功求解平均只覆盖约 1 个内环周期。

`mpc_solve()` 的到期时间是 13 项取 min，其中包含 `actuator_capability->header.valid_until_us` 与 `actuator_status->header.valid_until_us`；而执行器侧 `actuator_guard.c` 的 `header()` 把 `valid_until_us` 设为 `now + 5000`（**5 ms**）。5 ms TTL 的执行器消息决定了 MPC 快照的全部有效期。

这解释了 `outer_mpc_used = 80 / 9760`：不是 MPC 求解不出来（那是 4.1% 的另一个问题），而是**求解出来也几乎立刻过期**。

## 4.3 第 37 轮：移除执行器 TTL 的实验

把 `actuator_capability->header.valid_until_us` 与 `actuator_status->header.valid_until_us` 从 `mpc_solve()` 的 13 项到期取 min 中移除（其余不动），重建后运行 `verify_flight_entries`：

```
ENTRIES=PASS max_alt=2.098
```

与基线完全一致。也就是说，**让 MPC 快照不再被执行器 5 ms TTL 掐住，不会破坏当前 MIL 场景**。

但这一轮**没有测量参与度**（`outer_mpc_used` 需要消费侧诊断，本轮已回退），因此不能宣称"修好了 MPC 参与度低"。可确认的只有：该改法在既有验收场景下是无害的。

对照两次实验的差异值得记录：

| 实验 | 求解次数 | 快照到期链 | 飞行 |
|---|---|---|---|
| 收紧求解器容差 | 468 | 未改（被 5 ms 掐住） | **失败** |
| 移除执行器 TTL | 20 | 改（不再被掐住） | **通过** |

收紧求解器那次的失败因此不能用"MPC 被用得更多"解释——当时快照仍只活 1 ms。更可能是额外求解改变了 `m6.solver_failures` 计数、健康上报或 seed 路径。这一点需要在修好有效期之后重新验证，两个因素不能混在一起判断。

## 4.4 第 37 轮续：应用有效期修复后的原始数字

在 4.3 的基础上保留修复并记录消费侧时间戳，26 s MIL：

| 指标 | 修复前 | 修复后 |
|---|---|---|
| `life_us`（`expires - sample`） | 8,000 | **23,000** |
| `used_samples`（采用 MPC 的内环周期） | 80 | **171** |
| `solved`（求解成功数） | 20 | **9** |
| `expires_minus_eval_us`（消费时剩余） | 1,000 | **1,000** |

两点结论与一点告诫：

1. **有效期确实被拉长了**：从导航采样算起 8 ms → 23 ms，这部分修复有效、可复现；
2. **采用数翻倍但仍很低**（80 → 171 / 9760），而消费时剩余寿命仍是 1 ms，说明限制因素不只是到期链——`evaluation_time - sample_time` 本身在不同周期里很大；
3. **单点样本不可靠**：`expires_minus_eval_us` 与我先前记录的 `eval - sample`（7 ms 与 22 ms 两个不同值）都只是"最后一个被采用的样本"，不能代表分布。要下结论必须记录分布（最小值、中位数、最大值），而不是单个末值。

`solved` 从 20 降到 9 也需要解释（控制行为改变后参考轨迹不同），但同样不能凭单次运行定论。

诊断代码已回退。**下一阶段应先补"分布统计"这一课，再判断有效期修复是否足够**——否则会像本轮一样，用一个末值去推断整体。

## 4.5 第 38 轮：按 job 记录分布，两项根因分别定量

第 37 轮末的告诫是"先补分布统计，再判断"。本轮把诊断做成固件侧证据通道（`middleware/model/control/mpc_diagnostics.h`，Host 构建才落盘，不改变任何控制决策）：

- `m6_jobs.json`：每个 job 的首个拒绝阶段、solver status、primal/dual residual、独立约束违反量、推力超出量、首控制量、seed，以及 `sample/control/evaluation/expires` 四个时间戳；
- `m6_runtime_stats.json` 的 `consumer`：9760 个 1 kHz 消费点里每个备份条件的独立计数、剩余寿命直方图、MPC 与 PD 回退量的逐轴差值。

### 4.5.1 拒绝全部落在同一个阶段

488 个 job 的分布（26 s MIL，基线）：

| 指标 | 值 |
|---|---|
| 首个拒绝阶段 | `RESIDUAL` 468 个，`OK` 20 个；没有 `DOMAIN`/`REFERENCE`/`BOUNDS`/`SOLVER_CALL`/`SOLVER_STATUS`/`NON_FINITE`/`PRIMAL`/`THRUST` 拒绝 |
| solver status | 488 个 job 全部 `CONTROL_SOLVER_SOLVED`（1） |
| primal residual | min 4.7e-9，median 3.0e-8，max 1.35e-3 |
| dual residual | min 1.31e-4，p25 1.37e-3，**median 1.75e-3**，p75 3.51e-3，max 1.00e-2 |
| 独立约束违反量 | 0（p75 及以下全为 0），max 8.6e-4 |
| 推力超出量 | 0 |

结论：**失败与 QP 组装、预测模型、变量单位无关**。独立可行性检查（A·x 对原始约束、推力幅值）在所有 job 上都通过，primal 残差已达到 1e-8 量级。唯一的拒绝原因是应用侧对 dual residual 的**绝对** 1e-3 门限，而 OSQP 生成工作区里 `eps_abs = eps_rel = 1e-3`，其停止准则是 `1e-3 + 1e-3·max(‖Px‖,‖A'y‖,‖q‖)`，对本 QP 约 2e-3。实测 median 1.75e-3 正好落在 OSQP 自己的容差内：求解器按合同收敛，应用侧按更严的绝对量判负。

### 4.5.2 让求解器满足既有门限之后，飞不起来

只改求解器、**不动 1e-3 门限**（`eps_rel = 0`，按绝对 1e-3 终止）：

| 指标 | 基线 | `eps_rel = 0` |
|---|---|---|
| solved / jobs | 20 / 488 | **489 / 489** |
| max primal / dual residual | 1.35e-3 / 1.00e-2 | 9.83e-4 / 9.98e-4 |
| 被采用的 1 kHz 周期 | 80 / 9760 | **1956 / 9780** |
| 备份原因 | 9680 全部为过期 | 7824 全部为过期 |
| `limit_rejected` / `bounds_rejected` | 0 / 0 | 0 / 0 |
| **MIL 最大高度** | **2.098 m** | **0.242 m** |
| TAKEOFF（t=6.0 s）ACK | ack=1 接受 | **ack=0，reason=5（`land != LANDED`）** |

MPC 与 PD 的差值在同一轮里被逐轴记录（1956 个采用点）：x 轴 −0.330…+0.013，y 轴 −0.014…+0.326，z 轴 **−0.161…0.000** m/s²。也就是说 MPC 的水平指令与 PD 相差不超过 0.33 m/s²，**z 轴只会比 PD 更"向上"、从不更向下**。

把 0.33 m/s² 的量级放进 20% 的占空比，无法解释高度从 2.098 m 掉到 0.242 m。真正发生的是**时序**：地面保持阶段 MPC 的零偏让飞行器提前离地 0.24 m，LandDetector 不再报告 `LANDED`，于是 6.0 s 的 TAKEOFF 以 `reason=5` 被拒且不重发——验收场景再也不可能起飞。这与第 37 轮"收紧求解器 → 起飞失败"的现象一致，并且首次给出了机制，而不是"MPC 有害"的笼统说法。

> **第 39 轮更正（量级检查 → 已用实测否证）**：上段的"地面段零偏抬升"机制**不成立**。
>
> 第 39 轮在 `mpc_diagnostics.h` 增加了起飞窗口的 1 kHz 使用轨迹（`m6_use_trace.json`，记录每 tick 的 `backup`、MPC 与 PD 三轴加速度），并在两种构建上各跑一次 26 s MIL：
>
> | 构建 | 窗口 tick | 采用 MPC 的 tick（< 6.0 s） | 占空比 | z 轴 MPC−PD |
> |---|---|---|---|---|
> | 基线（`eps_rel=1e-3`） | 2040 | 8 | **0.4%** | max −0.1597 |
> | `eps_rel=0`（全解） | 2060 | 352 | **17.1%** | mean **−0.0859**，max −0.1597 |
>
> 有效平均偏置 = 0.171 × 0.0859 = **1.47e-3 m/s²**；在 1.8 s 内给出 Δv ≈ **2.6 mm/s**、Δh ≈ **2.4 mm**。
> 观测到的是 **242 mm**，相差约 100 倍。**因此"MPC 在地面段把飞行器抬起来"被直接测量否证**，不能再作为修复依据。
>
> 剩下的解释必须落在"接受解"带来的**非加速度**差异上：`eps_rel=0` 让 `m6.solver_failures` 从约 488 变成 0，控制器健康/能力上报随之改变；若 FMS 的离地判定或起飞前置条件读取了控制健康/求解失败计数，就会出现"加速度只差 2 mm、状态却完全不同"的结果。**下一步的判别测量**是把两种构建的 `ControlHealth`、`solver_failures`、FMS `land.state` 与 `prearm` 逐 tick 对比，而不是继续调 MPC 代价或门限。

本轮实验已整条回退（`eps_rel` 恢复 1e-3，MIL 回到 2.098 m / TAKEOFF ack=1），只保留诊断通道。

### 4.5.3 快照寿命的分布（不再是末值）

基线 20 个成功 job 的 `expires - sample` 恒为 **8000 µs**，`expires - evaluation` 恒为 **5000 µs**；`evaluation - sample` 恒为 **3000 µs**。5000 µs 恰好等于 `actuator_guard.c` 的 `valid_until_us = now + 5000`，与 §4.2 的判断一致，并且这次是每个 job 的完整分布，不是最后一个样本。

### 4.5.4 下一阶段的入口

按依赖顺序：

1. **地面段与空中段分离**：MPC 的零偏在 `LANDED` 期间必须不改变离地判定（例如地面段不采用 MPC 快照，或采用但把净加速度限幅到不产生升力），否则任何提高接受率的修复都会以 `reason=5` 失败。这是"接受率"与"起飞前置条件"的耦合，不能用调容差绕过。
2. **快照到期链**：把 `actuator_capability/status` 的 5 ms 消息 TTL 从计划有效期里移除。计划不是执行器遥测的函数——这两项根本不进入 QP——5 ms 是消息新鲜度契约，不是计划有效期。§4.3 已证明该改动在既有场景下无害。
3. **门限与求解器的一致性**：1e-3 门限保留，把 OSQP 的终止准则改成绝对（`eps_rel = 0`，或重新生成工作区）。第 1 项完成前不得单独启用。

## 5. 边界

本节只确认了消费路径、拒绝阶段分布与"接受率—起飞前置条件"的耦合，**没有**修复任何控制律，也没有放宽容差。第 37 轮的两次实验与第 38 轮的 `eps_rel` 实验均已回退，当前 Flight 工作树只包含诊断通道（`mpc_diagnostics.h`、`mpc.c` 的记录点、`position_control.c` 的消费计数）与 `mpc_consumer_reset()` 的调用点。
