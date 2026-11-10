# FMAT-0009（草案）：Plant SensorKinematics 加速度通道构建相关数值异常

- 严重级别：中（阻断 `run_component_checks` 全链路，但不影响 MIL/回放与已验收组件门）
- 发现于：FMAT-0008 验收（RUN_ID `20261110T081853514Z_324d166`）
- 关联分支：`optimize/sil-physical-parameter-alignment`
- 状态：OPEN（待复测）
- 说明：本单与 FMAT-0008 主题（ARM 首次控制参考竞态）无技术关联，从 FMAT-0008 中拆出单独立项。

## 1. 现象

`tests/verify_plant_open_loop.m` 的 P-07（IMU/天线杆臂刚体运动学）断言失败：

```
accel err=3.895e-02   pos err=0.000e+00   vel err=0.000e+00
got=[0.438949 -0.00155877 -9.80665]   expected=[0.4 0 -9.80665]
```

同一断言中天线位置与天线速度**逐位精确通过**，只有 IMU 加速度的向心项偏大。

## 2. 已建立的定量事实

四组对照（同一模型，只改角速度与 IMU 杆臂；`SensorParameters(14:16)` 为 IMU→CG，`(17:19)` 为 IMU→天线）：

| 工况 | 杆臂 | 角速度 | 实测 accel |
|---|---|---|---|
| A | 0.10 | 2 | `[0.438949, -0.001559, -9.806650]` |
| B | 0.10 | 0 | `[0.000000, 0.000000, -9.806650]` |
| C | 0.00 | 2 | `[0.038949, -0.001559, -9.806650]` |
| D | 0.00 | 0 | `[0.000000, 0.000000, -9.806650]` |

推断：`A − C = 0.400000` 与 `ω²·r` 完全一致（参数与向心项公式正确）；`B = D` 说明偏差依赖角速度；`C` 在杆臂为 0 时仍有 `0.038949`，等价于 **`ω² × 9.737 mm` 的额外等效杆臂**。该 9.737 mm 既不在传入参数中，也不出现在组件内任何可打印的中间量中。

## 3. 已排除的候选

| 候选 | 排除依据 |
|---|---|
| 杆臂参数读取错误 | 打印 `lever_imu = -0.100000 / -0.000000` 与传入一致；天线位置/速度精确通过 |
| 向心项公式错误 | 打印 `centripetal_imu = [0.400000, 0, 0]`（工况 A）与 `ω²r` 一致 |
| 有限差分项污染 | 打印 `accel_cg_ned = [0,0,0]`、`imu_derivative_valid=1`、`x[3:5]=prev=[0,0,0]` |
| 角加速度项 | 打印 `alpha_cross_imu = [0,0,0]`（恒定角速度） |
| 安装矩阵/偏置/刻度/噪声 | 打印 M 为单位阵、bias=0、scale=0；`MᵀM·ideal` 与理论一致 |
| 模型链路附加环节 | `FMT_PlantSensors` 仅 1 个 S-function + 2 inport + 1 outport（3 条连线） |
| 测试顺序/状态泄漏 | 同一 MATLAB 会话内前后两次探针结果一致（均为 0.438949），且与是否先跑其它 Plant 测试无关 |
| 是否与 FMAT-0008 改动相关 | P-07 只使用 Plant 模型，不经过 FMS/引导/适配器；`origin/main` 无该测试段落 |

## 4. 未解释的关键矛盾（本单核心）

同一份源码、同一组输入，**结果随构建变化**：

| 构建 | 结果 |
|---|---|
| 含临时 `fprintf` 诊断 | `ideal = measured = [0.400000, 0, -9.806650]`（即断言期望值） |
| 干净源码重建 | `[0.438949, -0.001559, -9.806650]` |

这属于未定义行为（UB）或工具链相关行为的典型特征，需在 Simulink/mex 之外定位。

## 5. 建议的下一步

1. 把 `mdlOutputs` 中的数学部分（从杆臂计算到 `sensor[...]` 赋值）抽取为纯 C 函数/头文件，由 S-function 与独立测试程序共用；
2. 用独立测试程序传入 P-07 的固定输入（`x`、四元数、角速度、`SensorParameters`、`SensorModelParameters`、`SensorTimingParameters`），检查 `accel_ideal_body` 与 `sensor[3:5]`：
   - 若独立程序得 0.4 而 mex 得 0.4389 → 问题在 mex/Simulink 层（输入数据或编译选项）；
   - 若独立程序也得 0.4389 → 数学实现中确有未被静态阅读发现的错误；
3. 若判定为 UB：对抽取后的数学函数用 `gcc -fsanitize=address,undefined` 构建并跑 P-07 输入；
4. 对比 `mex` 编译选项（`-O2` vs `-O0`、`-ffp-contract`）对结果的影响（此前用 `mex('-O0',...)` 直接传参失败，需通过 `COMPFLAGS` 配置）。

## 6. 复现

```powershell
cd E:\Flight\Flight_Matlab_Test
matlab -batch "cd(pwd); addpath('tools'); addpath('tests'); addpath(fullfile(pwd,'models','plant')); flight_startup; try, verify_plant_open_loop; catch e, disp(e.message); end"
```

四组对照可用 `work/p07_matrix.m`（隔离运行该传感器模型并扫描杆臂/角速度）复现。

## 7. 影响

- `run_component_checks` 因此单中断（P-07 之前与之后的所有门均已单独验证通过）；
- 不影响 MIL 全链路、DataSIM/ExtINS 回放、源指纹与其余 11 个组件门；
- 不构成 FMAT-0008 的回归。
