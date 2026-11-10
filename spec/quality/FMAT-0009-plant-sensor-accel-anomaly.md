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

已排除“陈旧 mex”这一解释：删除 `work/mex/fmt_plant_sensors_sfun.*` 后强制重建（产物 30208 字节、时间戳刷新），P-07 仍以 `0.438949` 失败；而同一输入在带诊断 `fprintf` 的构建里输出 `ideal=[0.400000, 0, -9.806650]`、`sf=[0.399680, 0.015996, -9.806650]`（`sf0 = R00·0.4` 完全正确）。

这属于未定义行为（UB）或编译布局敏感行为：新增一条 `fprintf` 就会改变结果，说明 S-function 内部存在未初始化读取或越界访问（所有局部量在静态阅读中均已赋值，故 UB 更可能藏在辅助函数或参数索引路径里）。

## 4.1 编译器对比（本轮新增，关键）

同一份源码、同一组输入，按不同 mex 配置构建后运行：

| 构建配置 | 结果 | 判定 |
|---|---|---|
| MSVC（`mex -setup` 默认，`/O2`，即 `build_native_kernels` 实际使用） | `[0.438949, -0.001559, -9.806650]` | ✗ 与解析解不符 |
| MinGW GCC（`mex -f mingw64.xml`，该配置 `CFLAGS` 无优化，等同于 `-O0`） | `[0.400000, 0.000000, -9.806650]` | ✓ 与分析解一致 |
| MinGW GCC + `-O0 -fsanitize=undefined -fno-sanitize-recover`（`work/mingw64_ubsan.xml`） | `[0.400000, 0.000000, -9.806650]`，**UBSan 无告警** | ✓ |

结论：更可能是 **MSVC 优化暴露的未定义行为**（或 MSVC 特定语义），而非算法错误——GCC 构建直接给出正确值，UBSan 在 GCC 下无任何报告。

## 4.2 诊断打印放置的注意事项（供后续复现者参考）

在 `mdlOutputs` 中读取 `accel_ideal_body` 必须放在其计算循环**之后**；放在循环之前会读到未初始化值，曾导致“打印值与落盘值不一致”的误判。正确位置（计算循环之后、`fmt_measure_vector` 之前）的观测为：

```
A: ideal=[0.400000000 0 -9.806650000] sf=[0.399680043 0.015995734 -9.806650000]
   rot0=0.999200107 rot3=0.039989334 rot6=0.0   → 输出 [0.4, 0, -g] ✓
C: ideal=[0.000000000 0 -9.806650000] sf=[0.000000000 0 -9.806650000] → 输出 [0, 0, -g] ✓
```


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

## 8. 第二轮进展（GCC 构建后）

用 `mex -f matlabroot/bin/win64/mexopts/mingw64.xml` 构建该 S-function 后：

- P-07 **第一项断言（杆臂向心项）通过**：`ideal = measured = [0.400000, 0, -9.806650]`；
- P-07 **第二项子测试（2 ms 采样间隔）仍失败**，误差集中在加速度 x 通道：

```
got=[1.307812563 -20.800518439 -9.456650000]
exp=[1.315879362 -20.800521677 -9.456650000]
diff=[-8.067e-03  3.237e-06  0.000e+00]   (容差 1e-6)
```

即：静态旋转工况的偏差（9.7 mm 等效杆臂）由 MSVC 构建引入；动态工况下还存在约 8e-3 的 x 通道误差，两者可能同源（加速度装配），也可能是一个独立的误差项（例如角加速度/向心项的时间基准不一致：`alpha` 用区间平均、而 `ω×ω×r` 用区间末端角速度）。

后续建议：在动态工况下分别打印 `alpha_cross_imu` 与 `centripetal_imu` 的分量，与解析值（`avgAA × r` 与 `ω(2ms) × (ω(2ms) × r)`）逐项对比，确认 8e-3 来自哪一项；若来自 `alpha` 的时间基准，则应改用与速度差分相同的区间平均口径。
## 9. 第三轮进展（动态工况逐项对比）

在 2 ms 采样间隔子测试（`sampleTimingParameters(1)=2000`）下打印组件内部量，与解析值逐项比对，**全部精确一致**：

```
[dyn] t=0.00200 dt=0.002000
      cg=[1.300000 -0.700000 0.350000]        ← 与 avgA = a0 + 0.5·j·P 一致
      alpha=[0.000000 -20.100000 0.000000]    ← α_avg×r，α_avg = 201，r = -0.1 m
      cent=[0.016160 0.000000 -0.000000]      ← ω(2ms)²·0.1，ω(2ms) = 0.402
      w=[0.000000 0.000000 0.402000]          ← 与解析角速度一致
```

而最终输出仍差 `x = -8.067e-03`（y 差 3.237e-06，z 精确），且该残差满足 `≈ 2·g·yaw`（yaw(2 ms) = 4.013e-4 → 2×9.80665×4.013e-4 = 7.87e-3）。这说明：

- 有限差分、角加速度项、向心项、Coriolis 项**都没有问题**；
- 残差只可能来自「体→NED→体」的旋转换算环节——重力项与杠杆项在此环节被旋转的次数不一致（等效于对重力多做了一次 θ 旋转）；
- 静态工况（yaw = 0.04）用 GCC 构建时却精确通过，说明该不一致的具体触发条件与工况相关，需要针对旋转矩阵的构造与使用位置逐行核对（`fmt_rotation` 的返回约定 vs `accel_ideal_body` 的索引约定）。

### 建议定位位置

`fmt_plant_sensors_sfun.c` 中三处使用 `rotation` 的地方：

1. `accel_imu_ned[i] += rotation[3*i + j] * accel_imu_body[j];`（体→NED）
2. `sensor[FMT_SENSOR_POSITION+axis] += rotation[3*axis+i] * lever_ant[i];`（体→NED）
3. `accel_ideal_body[axis] += rotation[3*i + axis] * specific_force_ned[i];`（NED→体）

若 1) 与 3) 使用同一 `rotation` 且二者互为转置，则结果精确；残差说明其中一处缺少/多了一次转置，或 `fmt_rotation` 的返回约定与调用处索引约定不一致。
## 10. 旋转约定核对结果（排除转置假设）

`fmt_rotation`（`models/plant/fmt_rotation.h`）返回**行主序 C_ned_from_body**（体→NED），与测试侧 `reference_rotation` 的实现逐元素一致。三处使用点核对：

| 使用点 | 索引形式 | 数学语义 | 结论 |
|---|---|---|---|
| `accel_imu_ned[i] += rotation[3*i + j] * accel_imu_body[j]` | 行 i | `(R·v)_i`，体→NED | 正确 |
| `sensor[FMT_SENSOR_POSITION + axis] += rotation[3*axis + i] * lever_ant[i]` | 行 axis | `(R·lever)_axis`，体→NED | 正确 |
| `accel_ideal_body[axis] += rotation[3*i + axis] * specific_force_ned[i]` | 列 axis | `(Rᵀ·sf)_axis`，NED→体 | 正确 |

因此 §9 提出的「转置不一致」假设**不成立**，动态工况 8e-3 残差另有来源。剩余可能：

1. 测试侧与组件侧对「区间平均」的定义不同（例如 `avgAA` 用 0.5·jerk·P，而组件用 `(ω(2ms)-ω(0))/dt`，二者在加速度为常数+jerk 时应一致，但若组件实际用的是 `(ω(2ms)-ω(1ms))/dt` 则不同）；
2. `specific_force_ned[2] -= gravity` 之后，`accel_ideal_body` 的索引虽然正确，但 `gravity` 的符号/参考系在动态工况下与其他项不同源；
3. 测试的 `velocityImuNed` 与组件的 `velocity_imu_ned` 在「是否包含 Coriolis 前置项」上不一致（当前 earth rate 置零，影响应为 0，但需确认置零的确实是 earth rate 而不是 magnetic field）。

建议下一步：在动态工况下同时打印组件的 `specific_force_ned` 与测试侧同样公式算出的期望值，逐分量比对，即可把残差锁定到上述三者之一。