# Plant 模型接口

本目录包含 SIM_ONLY 四旋翼物理模型的 Simulink S-Function 内核。Flight 固件本身不依赖这些文件；MATLAB Plant 只用于 MIL 和算法验证。

## PlantState（17 doubles）

1. p_NED_m[3]
2. v_NED_mps[3]
3. q_0b_wxyz[4]：scalar-first，body FRD 到固定 N0
4. omega_b_N0_FRD_radps[3]
5. motor_omega_radps[4]

## Environment（15 doubles）

| MATLAB 下标 | 内容 | 单位/坐标 |
|---|---|---|
| 1:3 | wind_NED | m/s |
| 4:6 | external_force_NED | N |
| 7:9 | external_torque_FRD | N·m |
| 10 | ground_enable | 0/1 |
| 11 | drag_enable | 0/1 |
| 12:15 | rotor_effectiveness | 0..1 |

RotorWrench/GroundWrench 均为 FRD 六维 wrench。刚体内核将机体系力旋转到固定 NED；Environment 的外力已是 NED，外力矩是 FRD。

## PlantParameters（26 doubles）

`[mass, J(:), kf, motor_tau, dragN, dragE, dragD, rate_damping, ground_k, ground_c, ground_D, contact_lever_F, contact_lever_R, contact_lever_D, gravity, skid_half_x, skid_half_y, ground_friction]`

`J(:)` 是完整 3×3 转动惯量矩阵，按 MATLAB 列优先顺序展开，占 9 个元素。刚体内核计算 `J*omega`、`omega×J*omega` 和 `J\\rhs`，支持非对角惯性耦合；参数必须对称正定。所有单位见 spec/QuadPlant-system.md。参数向量长度固定为 26。

## Fail-closed 约束

- 所有状态、参数、wrench 和环境元素必须有限。
- 质量、惯量矩阵正定性、电机推力系数、电机时间常数、地面刚度和重力必须满足正值约束。
- 阻力、角阻尼、接触阻尼、摩擦和 skid 半跨距不能为负。
- 四元数范数必须非零；四路电机转速不能为负。
- ground/drag flag 必须严格为 0 或 1；rotor_effectiveness 必须在 [0,1]。
- 无效输入由 S-Function 报错，不得用 NaN 传播或静默裁剪掩盖。

重建原生内核：在 MATLAB 打开项目后执行 build_native_kernels；重新生成模型图执行 build_plant_models。运行测试执行 verify_plant_open_loop。这些命令必须在具备 MATLAB/Simulink 和项目依赖的本机环境运行。
