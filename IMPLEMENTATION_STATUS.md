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

本阶段在独立优化分支中完成代码修改，尚未在 MATLAB/Simulink 环境执行，因此不计入上表的实测通过结果。

- 完整 3×3 对称正定惯量矩阵：保留 J(:)，计算 J·omega、omega×(J·omega) 和 J⁻¹角加速度。
- 统一 PlantState（17）、Environment（15）和 PlantParameters（26）接口合同。
- S-Function 增加参数、状态、wrench、环境和输出有限值校验；非法布尔量、电机效能越界、非对称/非正定惯量拒绝。
- 地面接触增加静态 mg/k 支撑测试；数值验证增加独立 250 μs RK4 参考。
- 当前代码覆盖 P-01～P-06、P-11～P-13、P-15～P-20；P-07～P-10 和 P-14 尚未实现。

本阶段的退出条件是：在用户 MATLAB 环境成功执行 build_native_kernels、generate_parameters、verify_parameter_view 和 verify_plant_open_loop，确认报告与当前分支一致。Plant 报告在剩余用例完成前必须保持 PARTIAL，不能解释为完整物理模型验收或实机验证。
