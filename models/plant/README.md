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

[mass, J(:)(9, MATLAB column-major), kf, motor_tau, dragN, dragE, dragD, rate_damping, ground_k, ground_c, ground_D, contact_lever_F, contact_lever_R, contact_lever_D, gravity, skid_half_x, skid_half_y, ground_friction]

J 必须是完整的对称正定 3×3 矩阵。当前 Flight SIM_ONLY 数值恰好为对角矩阵。所有参数单位见 spec/QuadPlant-system.md。

第一版 SIM_ONLY 地面摩擦系数设置为 0，不产生水平接触力；保留该参数位是为了后续有明确证据时扩展，不代表当前已验证摩擦模型。

## Fail-closed 约束

- 所有状态、参数、wrench 和环境元素必须有限。
- 质量、电机推力系数、电机时间常数、地面刚度和重力必须为正；惯量必须对称正定。
- 阻力、角阻尼、接触阻尼、摩擦和 skid 半跨距不能为负。
- 四元数范数必须非零；四路电机转速不能为负。
- ground/drag flag 必须严格为 0 或 1；rotor_effectiveness 必须在 [0,1]。
- 无效输入由 S-Function 报错，不得用 NaN 传播或静默裁剪掩盖。

重建原生内核：在 MATLAB 打开项目后执行 build_native_kernels；运行参数检查执行 generate_parameters 和 verify_parameter_view；运行物理组件检查执行 verify_plant_open_loop。这些命令必须在具备 MATLAB/Simulink 和项目依赖的本机环境运行。


## SensorParameters（19 doubles）

[gravity, magnetic_field_NED(3), earth_rate_NED(3), initial_velocity_NED(3), initial_rate_FRD(3), imu_to_cg_FRD(3), antenna_from_imu_FRD(3)]

该向量用于确定性基础传感器模型。IMU 杆臂按 CG→IMU = -imu_to_cg 解释；GNSS 天线杆臂为 CG→IMU + IMU→antenna。IMU 比力包含杆臂切向/向心加速度、固定 N0 Earth-rate 和 Coriolis 项。初始速度/角速度用于初始化差分状态，避免首样本产生人为导数脉冲；首个 IMU 差分尚未有效时，IMU valid 位保持清零。

P-07/P-08 覆盖杆臂运动学、静止比力、Earth-rate gyro 和移动时 Coriolis。

## SensorModelParameters（54 doubles）

[seed, imu_installation(9 row-major), mag_installation(9 row-major), gyro_bias(3), accel_bias(3), mag_bias(3), gyro_scale_error(3), accel_scale_error(3), mag_scale_error(3), gyro_noise_std(3), accel_noise_std(3), mag_noise_std(3), gnss_position_noise_std(3), gnss_velocity_noise_std(3), baro_noise_std, baro_bias]

当前 `scale_error` SIM_ONLY 配置按轴复制到 gyro/accel/mag 三组残余比例误差。bias/scale/noise 在模型的 M2 标准样本出口注入；安装矩阵从传感器轴旋转到 FRD。噪声由固定 seed、source、物理 sample index 和 axis 无状态生成，IMU/MAG/GNSS/Baro 分别按 1 kHz/100 Hz/10 Hz/50 Hz 的噪声样本索引取值，不依赖 Plant RK4 子步数。随机 seed 仅用于可重复仿真，不代表传感器实测噪声标定。

P-09 的脚本覆盖同 seed 可复现、不同 seed 序列变化、IMU 噪声 STD 95% 卡方区间、轴间相关性以及 bias/scale 注入。SensorTimingParameters 为 10 doubles：[imu_period, mag_period, baro_period, gnss_period, imu_pipeline_delay, imu_transport_delay, mag_transport_delay, baro_transport_delay, gnss_transport_delay, imu_pipeline_uncertainty]。该向量由参数生成器写入数据字典，并由 MIL Host SIL 运行时的 `fmt_sensor_simulation` 事件队列消费，不在 Plant Sensor S-Function 内延迟信号。队列以固定 500 μs 步进独立释放 IMU/GNSS/MAG/Baro 事件，事件携带 sample/capture/arrival/release 时间和序号，arrival 表示物理传输完成，release 表示 500 μs 调度步实际交付固件；统计 opportunities/generated/suppressed/released/accepted，检查缺测序号缺口、队列守恒、时钟步进和固件 sample-validity expiry。`verify_sensor_event_timing` 是该子项的独立 MEX 验证入口，并由 `run_component_checks` 调用。

当前 GNSS PVT 以本地 FCU monotonic epoch 注入；PPS raw capture、UTC time observation 与跨时钟域映射尚未接入 Host SIL。配置 `pps_backend=DISABLED_LOCAL_MONOTONIC` 是有意的边界声明，不代表 PPS 验证通过。因此 P-10 整体保持 PARTIAL，不能将本队列测试解释为 GNSS 时间同步或 PPS 捕获验收。
