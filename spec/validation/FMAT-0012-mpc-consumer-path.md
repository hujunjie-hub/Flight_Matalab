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

## 5. 边界

本节只确认了消费路径与条件，**没有**定位到具体缺陷，也没有修改任何固件代码。三次实验的代码改动均已回退（Flight `8b938ca` 与后续 checkout），当前工作树干净。
