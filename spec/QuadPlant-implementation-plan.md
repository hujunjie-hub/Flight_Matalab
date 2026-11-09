# QuadPlant 实施计划

状态：P0～P2 已实现代码框架并进入验证；P3 传感器、P4 集成和 P5 系统闭环尚未验收。2026-11-09。

| 阶段 | 交付 | 当前状态/退出检查 |
|---|---|---|
| P0 物理接口冻结 | u/w/y/z bus、CG/frame/q/rate、参数表 | 已明确 17 维 PlantState 和 15 维 Environment；共享坐标契约进入代码 |
| P1 电机/载荷 | MotorDynamics、RotorWrench | 模型已存在；参数来源统一，需 MATLAB 运行 P-01～P-03 |
| P2 刚体/接触 | 17 维 PlantState、RK4、GroundContact | 模型已存在；完整 3×3 惯量、输入校验、静态支撑和步长参考测试已加入；需 MATLAB 运行 P-04～P-06、P-11～P-20 |
| P3 传感器 | 杆臂、Earth 项、noise/bias/delay | 未完成；P-07～P-10 |
| P4 物理侧集成 | FMT_QuadPlant/FMT_SensorSimulation | 模型结构已存在；仍需检查开环因果链、采样相位和输出单位 |
| P5 系统闭环 | M7 已提交帧、M2 标准入口 | 未开始验收；须待 FMS/Control 和传感器合格后运行 MIL |

共享质量、惯量、电机位置、偏航符号和电机推力限制以同级 Flight/config/vehicle_model.yaml 为准；Flight 文件目前仍是 SIM_ONLY 合成参数。Plant 专有的 k_f、阻力、接触参数和传感器合成参数留在 Flight_Matalab。帧量化 0～10 N 曲线是独立执行器夹具，不得与 Plant 15 N 物理推力上限混为一谈。

当前刚体内核已支持完整对称正定 3×3 惯量矩阵，参数合同使用 26 元素向量并保留 J(:)；P-20 覆盖非对角惯性耦合。该功能尚未在 MATLAB/Simulink 执行验证。

所有 C S-Function 对输入状态、参数、环境、wrench 和输出有限值做 fail-closed 检查。每阶段保存接口/模型 Hash 和测试结果；静态代码审查不能替代 MATLAB 编译、Simulink 运行或 HIL 验收。

物理 Plant 使用 double；公开固件兼容 bus 使用 single。每个新增 fidelity 层都需重新执行步长、能量、符号和传感器一致性检查。
