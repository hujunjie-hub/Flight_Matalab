# FMAT-0012 附记：MIL 中 MPC 输入的 5.2 s 时钟偏移

- 关联 Issue：Flight_Matalab#12
- 记录时间：第 14 轮排查
- 结论状态：**现象已定量，写入方未定**

## 1. 现象

26 s MIL 中 MPC 任务被调起 210 次，全部被 `controller_validate_input()` 以 `STATUS_STALE_DATA`（-10）拒绝，`mpc_solve()` 一次未执行。

`m6_runtime_stats.json` 实测：

```json
{
  "blocked_validation": 210,
  "blocked_uninitialized": 0, "blocked_mode": 0, "blocked_clock": 0,
  "blocked_stale": 0, "blocked_throttle": 0, "blocked_lock": 0,
  "last_validation_status": -10,
  "last_eval_age_us": 5200000,
  "max_eval_age_us": 5200000
}
```

`evaluation_time_us - control_time_us` 在 210 次调用中**恒为 5,200,000 µs**（既不随 tick 浮动，也不随时间增长）。

## 2. 已确定的事实

| 事实 | 依据 |
|---|---|
| 控制时刻取自 bundle 的导航采样时刻 | `applications/runtime/runtime_data.c:418` `input->control_time_us = bundle->nav.header.timestamp_sample_us;` |
| 评估时刻取当前运行时时钟 | 同文件 `:419` `input->evaluation_time_us = now;`，而 `now` 来自 `runtime_now_us()` → `clock_now_us()`（`runtime_internal.h:94`） |
| 5 ms 新鲜度规则 | `controller.c:135-141`：`evaluation - control + uncertainty > 5000` → `STALE_DATA` |
| 其余闸门均未触发 | 上一轮计数：mode/clock/stale/throttle/lock 全为 0 |
| 适配层时钟基 | `fmt_flight_runtime.c:566` `test_clock = {0x12345678, 1000000, 1, 0}`，每步 `+= 500`（`:690`） |

恒定 5.2 s 的差值说明**两个时间戳同速推进但基准不同**，而不是"bundle 没刷新"（那会让差值随时间增长）或"略微滞后"（那会随 tick 浮动）。

## 3. 尚未确定

`NavigationSnapshot.header.timestamp_sample_us` 的写入点尚未定位：

- `ins_interface.c` 只是转发 `ins_model_get_snapshot()`，实现位于 KF-GINS 后端（C++）；
- 在 `middleware/model/ins` 与 `applications/runtime` 下检索 `header.timestamp_sample_us =` 无命中，说明它由通用 header 辅助函数填充，字段名不是直接赋值形式；
- Host 侧 `clock_now_us`/`clock_read` 的最终定义者未确认：SIL 场景在 `tests/simulation/sil_flight.c` 里以 `test_clock` 实现，但该对象是否进入 DLL 链接、以及是否与适配层的 `test_clock` 是同一实例，需要看链接产物符号才能定论。

5.2 s 与 ARM ACK 时刻（5.220 s）数值接近，但**这只是相关性**，不能据此下结论。

## 4. 下一步（按成本排序）

1. 用 `nm` 查 DLL 里 `clock_now_us`、`clock_read`、`estimator_get_snapshot` 的符号来源，确认 Host 侧到底有几个时钟实例；
2. 在 `runtime_data_controller_input()` 里临时打印 `bundle->nav.header.timestamp_sample_us` 与 `now`，在 1 kHz 的导航发布点同时打印，看偏移是在发布时就存在还是消费时才出现；
3. 依据结论三选一：修导航发布的时间戳来源、修 Host 时钟桥接、或修 bundle 刷新语义。

在写入方确认前不改代码——三种修法影响面不同，改错会掩盖真实问题。
