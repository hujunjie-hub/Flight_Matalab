# 实施状态

当前交付范围为 **Flight 固件 Windows Host SIL**。现行合同为 Schema 6.0、Product/Port `0x00010906`。三个顶层模型和共享飞控模型均已生成，并已注册到 MATLAB Project。

| 范围 | 实测结果 |
| --- | --- |
| Flight 固件基线 | 上游 Host SIL 通过 3,151 项检查，配置及源码共 457 个文件完成 SHA-256 核对 |
| 公共类型 | 重新从现行固件头文件生成 106 个值类型 Bus |
| MILSIM | 26 s 闭环，完成解锁、2 m 起飞、降落、上锁；实际最高 1.986 m，最终速度接近零 |
| DataSIM | 回放 MIL 标准工程量传感器与指令，诊断和四路提交推力逐样本一致 |
| ExtINS DataSIM | 在 M3 输出边界回放保存的导航快照和能力，飞行状态和四路提交推力逐样本一致 |
| 冷启动 | 独立 MATLAB 进程中，三个入口的默认输入冒烟和完整复跑均通过；MATLAB Project 9 项检查通过 |
| 缺测保护 | DataSIM 全传感器缺测时，解锁指令产生的提交推力持续为零 |

`implementation_manifest.json` 记录模型、录制数据、源码和仿真证据的完整性信息。单点接地在上锁后会倾倒，最终 SIM_ONLY 物理对象采用四点接地与正则化摩擦。ExtINS 的默认录制来源为 MIL 中的固件 KF-GINS。当前证据覆盖主机仿真与合成输入，STM32 时序、HIL 链路、实体执行器和实飞另行验证。



## Plant 物理模型第二阶段（代码状态）

以下是独立的 Plant 算法验证代码状态，不计入上表已实测通过的 Host SIL 结果。当前尚未在 MATLAB/Simulink 环境运行本阶段测试。

- Plant 参数合同扩展为 26 项：质量、完整 J(:) 3×3 惯量、k_f、电机时间常数、阻力、角阻尼、地面接触、重力和摩擦系数。
- 刚体角运动使用完整 J·omega、omega×(J·omega) 和 Cholesky 求解 J*alpha=rhs；参数入口拒绝非对称或非正定惯量。
- Plant S-Function 对状态、环境、wrench、参数和输出做有限值检查；ground/drag 开关严格为 0/1，rotor_effectiveness 限定 [0,1]。
- 第一版地面摩擦系数明确设为 0；增加静态 mg/k 支撑、无水平摩擦、FRD/NED 变换、风阻、250 μs 独立 RK4 参考和输入拒绝测试。
- 当前代码覆盖 P-01～P-06、P-11～P-13、P-15～P-21；P-07～P-10（传感器运动学/噪声/时序）尚未实现；P-14 已由 verify_truth_isolation 实现并纳入 run_component_checks。

本阶段需在用户 MATLAB 环境执行 run_component_checks；该入口会先运行输入预检、重建 build_native_kernels、生成参数字典，再执行 verify_parameter_view、verify_plant_open_loop 及已实现组件检查。也可单独执行 build_native_kernels、generate_parameters、verify_parameter_view 和 verify_plant_open_loop。必须保存实际运行报告、MATLAB 版本、求解器与模型 Hash。Plant 报告必须保持 PARTIAL，不能解释为完整物理模型验收、HIL 实时性 PASS 或实机飞行放行。
