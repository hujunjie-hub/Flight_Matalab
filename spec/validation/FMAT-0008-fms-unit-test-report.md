# FMAT-0008 FMS 单元测试报告

- 仓库：`hujunjie-hub/Flight`
- 分支：`fix/fmat-0008-first-reference-race`
- 提交：`b8ae3ed`（failsafe 首参考竞态修复 + 6 项测试）
- 套件：`tests/flight_management/test_m4_main.c`（FMS 主机测试）
- 结果：**checks = 993，failures = 0**

## 1. 测试范围

本 Issue 要求在「ARM 后首次控制参考尚未建立」的窗口内验证六类行为。对应测试与断言如下（全部新增于 `test_m4_main.c`，并注册到 `main()` 的用例表）：

| # | 用例名 | 目的 | 关键断言 |
|---|---|---|---|
| 1 | `arm_first_reference_partial_dof_no_terminal` | ARM 帧的 Control 能力必然只报部分自由度，不得据此锁存 TERMINAL | ARM 后 `failsafe_level != FAILSAFE_TERMINAL`；无 `CONTROL_ACTIVE`；窗口内再跑 50 ms 仍不锁存；`arm_state == ARMED` |
| 2 | `arm_first_reference_in_window_signs_permit` | 首个有效参考在窗口内到达时，必须能建立 CONTROL_ACTIVE | `failsafe_level != TERMINAL`、`arm_state == ARMED`，且 permit 含 `PERMIT_SCOPE_CONTROL_ACTIVE` |
| 3 | `arm_first_reference_window_expiry_inhibits_outputs` | 窗口耗尽时保持输出禁止，且迟到的参考不得复活 permit | `failsafe_level >= FAILSAFE_ACTION_REQUIRED`；permit 无 `CONTROL_ACTIVE`（含随后注入的参考） |
| 4 | `established_link_loss_keeps_terminal` | 已建立控制链路后，能力丢失必须立即 TERMINAL，窗口不得软化既有规则 | 部分 DOF 下 `failsafe_level == TERMINAL`、permit 无 `CONTROL_ACTIVE`；50 ms 后仍为 TERMINAL |
| 5 | `expired_reference_cannot_sign_in_window` | 过期参考不得签署；同一参考在有效 TTL 下必须能签署 | TTL=0 时无 `CONTROL_ACTIVE`；恢复 TTL 后签署成功 |
| 6 | `permit_rebind_keeps_revoked_watermark` | 撤销后的重绑定必须推进 epoch，不得复用撤销水位 | 撤销后 `permit_epoch > active_epoch` 且出现 `PERMIT_FLAG_REVOKED`；重绑定后 epoch 继续增大 |

对应任务书中的六条要求：①初始化截止时间为 0 不得立即触发终端保护 → 用例 1；②窗口内首个参考应建立 CONTROL_ACTIVE → 用例 2；③超窗保持输出禁止并执行既有安全策略 → 用例 3；④已建链后丢失参考原有保护继续有效 → 用例 4；⑤过期/错误 epoch/错误 reference ID 不得建立 permit → 用例 5（过期）+ 既有 `test_guidance_epoch_mismatch_has_no_permit`（epoch/ID）；⑥撤销与重绑定不得绕过 revoked watermark → 用例 6。

## 2. 反证（测试有效性）

把 `operator_authority.c` 的修复临时回退（`git stash` 该文件）后重新编译并运行同一套件：

```
FAIL arm_first_reference_partial_dof_no_terminal
FAIL arm_first_reference_in_window_signs_permit
checks=993 failures=4
```

用例 1、2 共 4 条断言失败，说明这两项测试确实咬住了「ARM 帧即锁存 TERMINAL」的缺陷；用例 3–6 在回退状态下仍通过，说明它们锁定的是**不得被削弱的既有规则**，与用例 1、2 形成互补约束。

## 3. 复现方式

```powershell
$f = 'E:\Flight\Flight'
$out = Join-Path $f 'build\m4_host'
New-Item -ItemType Directory -Force -Path $out | Out-Null
gcc -std=c11 -Wall -Wextra -Werror `
  -I"$f\middleware\model\fms" -I"$f\middleware\model\fms\quad_x4" `
  -I"$f\middleware\contracts" -I"$f\tests\flight_management" `
  "$f\middleware\model\fms\fms_interface.c" `
  "$f\middleware\model\fms\geofence_geometry\geofence_geometry.c" `
  "$f\middleware\model\fms\quad_x4\flight_state_machine\fms.c" `
  "$f\middleware\model\fms\quad_x4\mission_lifecycle\mission_lifecycle.c" `
  "$f\middleware\model\fms\quad_x4\operator_authority\operator_authority.c" `
  "$f\middleware\model\fms\quad_x4\flight_safety\actuation_permit.c" `
  "$f\middleware\model\fms\quad_x4\flight_safety\fms_safety.c" `
  "$f\middleware\model\fms\quad_x4\flight_policy\quad_x4_fms.c" `
  "$f\tests\flight_management\test_m4_main.c" -lm -o "$out\m4_host_tests.exe"
& "$out\m4_host_tests.exe"
```

预期输出末尾：`checks=993 failures=0`，退出码 0。

## 4. 相关套件

| 套件 | 用例数 | 结果 |
|---|---|---|
| FMS 主机测试（`tests/flight_management`） | 993 | 0 failures |
| M5 引导主机测试（`tests/guidance`） | 9515 | 0 failures（含新增 `landing_reference_probes_below_home`） |

## 5. 说明

- 主机测试仅证明算法与状态机在 Host 环境的行为，不构成 MCU 实时性、PIL/HIL 或实飞结论；
- `NOT_RUN` 类项目（如真实 TIM2 capture、UM982 UART/DMA）未因本报告改变状态；
- 本报告对应用户任务书中“FMS 单元测试报告”交付项。
