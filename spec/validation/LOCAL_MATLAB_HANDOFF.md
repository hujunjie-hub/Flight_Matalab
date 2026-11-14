# MATLAB 本地验证交接说明

版本：1.1  
更新日期：2026-11-14  
适用仓库：**hujunjie-hub/Flight_Matlab**  
唯一工作分支：**main**  
权威问题台账：GitHub Issues

> 本文是用户本地 MATLAB/Simulink 验证的操作手册。代码审查、静态检查和 GitHub CI 不能替代 MATLAB 实际运行。没有本地运行归档，不得把相应项目标记为 MATLAB PASS。

## 1. 当前工作规则

1. Flight_Matlab 与同级 Flight 均只使用 main 分支；当前两个仓库远程分支检查都只发现 main。不创建长期开发分支，不从旧 PR 分支拉取代码。
2. Flight_Matlab 与同级 Flight 必须配套。Flight 是固件参数、接口合同、TimeService、GNSS 和 UM982 parser 的权威来源。
3. 每次完整验证必须针对刚拉取的 main HEAD，并在归档中保留精确 commit。
4. 需要 MATLAB/Simulink 的验证由用户本地执行；开发侧负责代码、静态检查、测试入口、SPEC 和交接说明。
5. 未执行的测试保持 NOT_RUN；Plant 当前整体 PARTIAL 是预期边界；P-10 整体在板级证据齐全前保持 PARTIAL。
6. 不允许用放宽阈值、跳过候选验证、减少样本分母或延长旧数据有效期来制造 PASS。

## 2. 本地目录与环境

### 2.1 目录结构

两个仓库应放在同一个父目录下：

~~~text
<workspace>/
  Flight/
  Flight_Matlab/
~~~

本项目 MATLAB Project 文件在仓库中实际命名为 Flight_Matalab.prj（历史拼写如此，暂不重命名）。一键脚本通过 flight_startup 自动配置工程路径，不需要手工打开该文件；只有手工排障时才需要打开。

### 2.2 已知验证环境基线

| 项目 | 基线/要求 |
|---|---|
| 操作系统 | Windows 10/11 x64 |
| MATLAB | R2026b Update 1（既有证据环境；其他版本需单独记录） |
| Simulink | 与 MATLAB 同版本 |
| PowerShell | PowerShell 7，命令名 pwsh |
| Host SIL 编译器 | MinGW-w64 GCC；默认 D:\STM32CubeCLT\mingw64\bin |
| MATLAB MEX 编译器 | MATLAB 支持的 C 编译器；一键脚本会检查已选编译器，未选择时尝试 mex -setup C |
| ABI ARM 编译器（仅 FMAT-0018） | GNU Arm Embedded；默认 D:\STM32CubeCLT\GNU-tools-for-STM32\bin |
| Python | Python 3，可执行 python |
| 上游仓库 | 同级 Flight，commit 必须满足 config/flight_baseline.json 与 external_dependencies.lock.json |

如果编译器安装目录不同，在一键命令中使用 -GccDir 和 -ArmBin 参数。不要因为预检 Hash 不匹配而手工改锁文件；先核对 Flight commit 和路径。

## 3. 一键本地验证（唯一推荐入口）

### 3.1 只复制这一条命令

先在 Windows 文件资源管理器打开 Flight_Matlab 仓库根目录，在地址栏输入 pwsh 打开 PowerShell 7，然后整行复制执行：

~~~powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\run_local_validation.ps1
~~~

正常情况下，你不需要再分别执行 git pull、打开 MATLAB、复制 MATLAB 命令、手工归档或单独运行 ABI 命令。

### 3.2 这一条命令自动完成什么

脚本 tools/run_local_validation.ps1 会按固定顺序完成：

1. 检查 Git、Python、PowerShell 7、MATLAB 和 Host GCC。
2. 检查两个仓库是否有本地修改；如有修改，先将两个仓库 branch/HEAD/status 和待归档证据打包为失败交付包，不执行 reset、clean、切换分支或覆盖。
3. 自动 fetch 并 fast-forward 同步 Flight_Matlab/main 和同级 Flight/main。
4. 检查 `work/validation/` 是否有上一轮未归档证据；如有，自动将其原样打包为 `_DELIVERY.zip` + `.sha256`，不删除原件，并在启动 MATLAB 前停止。
5. 运行 `tools/test_local_validation_contract.py`，核对当前脚本、机器可读验收清单、交付文件和退出码规则是否一致；结果写入 `work/validation/local_validation_contract_test.txt`。该检查失败时会在启动 MATLAB 前停止，并保留日志。
6. 记录两个仓库的完整 commit SHA、MATLAB 路径、操作系统和编译器版本。
7. 用 MATLAB -batch 自动选择/检查 MEX C 编译器，执行唯一标准入口 `run_component_checks`。
8. 自动保存 MATLAB Diary 和 batch 控制台日志。
9. 无论 MATLAB 测试通过还是失败，都尝试归档本轮报告；不会因为测试失败而丢弃诊断证据。
10. 将本轮 `config/flight_baseline.json` 和 `scenarios/flight_sil_recording.mat` 一起放入 MATLAB 证据 ZIP。
11. MATLAB 归档完成后，自动运行 FMAT-0018 的 ARM/Host ABI 检查（默认工具链路径存在时）。
12. 生成一个总交付包及 SHA-256，方便一次性交回。
### 3.3 默认路径不同时，只复制这一条带参数命令

默认工具链路径：

| 工具 | 默认路径 |
|---|---|
| Host GCC | D:\STM32CubeCLT\mingw64\bin |
| GNU Arm | D:\STM32CubeCLT\GNU-tools-for-STM32\bin |
| MATLAB | 优先从 PATH 查找；否则自动查找 C:\Program Files\MATLAB\ |

如果你的安装目录不同，把路径替换后复制这一条：

~~~powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\run_local_validation.ps1 -GccDir 'D:\STM32CubeCLT\mingw64\bin' -ArmBin 'D:\STM32CubeCLT\GNU-tools-for-STM32\bin' -MatlabExe 'C:\Program Files\MATLAB\R2026b\bin\matlab.exe'
~~~

MatlabExe 可省略，只在 MATLAB 不在 PATH 且自动查找不到时填写。

### 3.4 如果脚本中途停止

- **提示仓库有本地修改：** 脚本会将 Flight_Matlab 和 Flight 两个仓库的 branch/HEAD/`git status`、上一轮待归档文件（如有）打包为 `_DELIVERY.zip` + `.sha256`，不执行 reset、clean、切换分支或覆盖原件；MATLAB 不会启动。只需交回这两个文件，等待审查。
- **本地交接合同预检失败：** MATLAB 尚未启动；脚本会自动生成 `_DELIVERY.zip` 和同名 `.sha256`，其中包含 `local_validation_contract_test.txt`、失败摘要和可用时的验收 manifest。只需交回这两个文件，不要自行修改脚本或 manifest。
- **发现未归档的上一轮报告：** 脚本会把 `work/validation/archives/` 以外的现有文件和目录原样打包为 `_DELIVERY.zip` + `.sha256`，不删除或覆盖原件；MATLAB 不会启动。只需交回这两个文件，不要自行删除或改名后强行重跑。
- **提示找不到 MATLAB：** 把实际 matlab.exe 完整路径填入 -MatlabExe。
- **提示 MEX C 编译器未配置：** 首次在 MATLAB Desktop 执行一次 mex -setup C，选定可用 C 编译器；之后重新复制上面的一键命令即可。
- **MATLAB 测试失败：** 脚本仍会尝试归档并生成总包。不要只发截图，交付总包和 SHA-256。
- **验收失败退出码：** MATLAB 进程失败、组件报告不是 PASS/PARTIAL_PASS，或 ABI 检查 FAIL 时，脚本会先生成总交付 ZIP 和 SHA-256，再以非零退出码结束。即使命令显示失败，也先检查交付包是否已生成并交回。
- **PARTIAL_PASS：** 属于当前已知未完成范围的部分通过，命令退出码可以为 0，但绝不等于完整 PASS；以总包内 RUN_ID_DELIVERY.txt 和 component_checks.json 为准。
- **ABI 工具链缺失：** MATLAB 验证仍会完成；总包说明中会写 SKIPPED_TOOLCHAIN_MISSING。补齐 ARM/Host 工具链后再做 ABI 专项复测。
- **归档脚本本身失败：** 不要删除 work/validation/，把整个目录交回。

脚本不会自动提交任何代码，不会自动改写 abi_lock.h，也不会添加 --emit-lock。ABI 检查生成的新证据会留在 Flight 工作区，等待审查；不要自行提交或清理。

## 4. 交付给验收方（只需要一个总包）

### 4.1 唯一必交文件

Flight_Matlab/work/validation/archives/RUN_ID_DELIVERY.zip

以及同名校验文件：

Flight_Matlab/work/validation/archives/RUN_ID_DELIVERY.zip.sha256

总交付 ZIP 内含：

- RUN_ID.zip：完整 MATLAB/Simulink 报告、Diary、源码/产物指纹、两个仓库 commit、环境信息、flight_baseline.json 和回放录制文件。
- RUN_ID.zip.sha256：MATLAB 证据包校验文件。
- RUN_ID_ABI.zip：FMAT-0018 ARM/Host ABI 报告、编译证据、命令清单、规范化布局文本及哈希清单（工具链可用时）。
- RUN_ID_ABI.zip.sha256：ABI 证据包校验文件（工具链可用时）。
- RUN_ID_DELIVERY.txt：本轮 commit、MATLAB 状态、ABI 状态和交付文件说明。
- `matlab_acceptance_manifest.json`：本轮完整验收范围及是否允许完整项目 PASS 的机器可读规则。

**你只需把 _DELIVERY.zip 和 _DELIVERY.zip.sha256 两个文件交给我。** 不需要逐个找 JSON、MAT、SLX、SLDD 文件，也不需要手工复制 commit SHA。

### 4.2 结果状态如何理解

- component_checks.json.status=PARTIAL_PASS：已实现的组件门禁通过，但 Plant/P-10 仍按设计边界保持 PARTIAL，不代表整机或板级通过。
- **完整项目 PASS 授权：** 当前 `matlab_acceptance_manifest.json` 的 `full_project_pass_allowed=false`，因为 P-10 Host MIL 物理 PPS/UART/DMA 链、板级/HIL 证据和当前 main 新鲜 MATLAB 复测尚未全部闭环。即使组件报告通过，也必须保持 `PARTIAL_PASS`；不得为了得到绿色状态自行修改该授权标志。
- component_checks.json.status=FAIL：存在失败项；仍然要把总包交回，不能跳过失败项。
- FMAT-0012 的 coverage_90 可能仍 FAIL，这是已知阻塞；不允许为了变绿而修改 90% 门槛或整轮分母。
- ABI FAIL 也必须保留报告交回，不能用旧证据覆盖新证据。
- ABI SKIPPED_TOOLCHAIN_MISSING 表示本轮没有生成新的 ABI 证据，不能视为通过。
- 一键命令退出码 0 表示本轮流程完成且总包已生成，不代表一定是完整 PASS；退出码 1 表示 MATLAB/组件/ABI 至少一项失败，但总包通常已在退出前生成。归档或打包本身失败时不会有完整总包，必须保留整个 work/validation/ 和终端输出。

### 4.3 下一轮运行前

本轮 ABI 工具运行后，Flight 仓库可能出现新生成的 tests/abi/evidence/ 文件变更。这是待审查证据，不要提交、reset 或 clean。把总交付包交回，等我审查并将需要保留的修改提交到 main 后，再开始下一轮。

## 5. 手工排障参考（通常不需要执行）

### 5.1 手工查看两个仓库状态

~~~powershell
git status --short
git branch --show-current
git rev-parse HEAD
git -C ..\Flight status --short
git -C ..\Flight branch --show-current
git -C ..\Flight rev-parse HEAD
~~~

### 5.2 手工打开 MATLAB 工程

只有一键脚本无法启动 MATLAB 时才手工操作：

1. 启动 MATLAB。
2. 打开 Flight_Matalab.prj。
3. 在 MATLAB 命令窗口执行 mex -setup C。
4. 按错误提示处理后，重新运行一键脚本；不要另外启动第二轮 run_component_checks。

### 5.3 单独排查依赖预检

正式一键验收会自动先重建 Flight Host SIL，再生成当前 flight_baseline.json 并运行预检。只有定位问题时才手工执行：

~~~powershell
pwsh -NoProfile -File .\tools\build_flight_runtime.ps1 -GccDir 'D:\STM32CubeCLT\mingw64\bin'
python -B .\tools\verify_inputs.py
~~~

预检失败时保留 work\validation\input_preflight.json 和完整日志，不得手工修改基线或锁文件绕过失败。

---

## 6. 如何登记 MATLAB 发现的问题

唯一登记位置：本仓库 GitHub Issues。模板位于：

.github/ISSUE_TEMPLATE/matlab-acceptance-issue.md

创建 Issue 时：

1. 标题先写 [MATLAB] 简短问题描述。
2. GitHub 分配 Issue 编号后，补正式 ID，例如 #18 对应 FMAT-0018。
3. 按模板填写严重级别、模块、被测 commit、Flight commit、MATLAB 版本、RUN_ID、测试 ID、复现步骤、期望/实际结果和证据 SHA-256。
4. 把 ZIP 附加到对应 Issue；若附件不可用，在 Issue 正文记录 ZIP 文件名、SHA-256 和交付日期。
5. 根因未确认时写“待定位”，把事实、推测和待验证假设分开，不要把推测写成根因。

严重级别：

- S0：安全边界、越权执行器输出或错误放行；
- S1：核心飞行、导航、控制、执行器或关键数据失效；
- S2：局部功能、诊断、数值或测试质量问题；
- S3：低风险维护性或文档问题。

问题状态由 Issue 正文的 Current status 维护。修复提交不等于问题关闭；只有修复 commit 对应的新 RUN_ID 回归通过，才可以进入 VERIFIED 并按关闭清单结案。

用户可以直接把 ZIP 和 SHA-256 文件交给验收方；验收方负责检查证据、建立/更新 FMAT Issue、安排修复并更新 SPEC。

## 7. 本轮已知问题与结果解释

当前仍需按以下边界判断，不能为了得到绿色结果而绕过：

| Issue | 当前状态 | 当前约束 |
|---|---|---|
| FMAT-0012 | BLOCKED | 488/488 MPC job 求解通过、消费点使用率 95.0%，但现有整轮覆盖率分母为 37.54%；等待用户确认口径，不改 90% 阈值或当前分母 |
| FMAT-0013 | BLOCKED | Flight M7 执行器侧 Ground Stop 证书、限速降推力和 ZERO_TARGET_APPLIED 回执已有 230/230 Host 检查；但当前 FMS 仍未用该回执驱动状态迁移：fms_build_ground_stop_certificate 要求快照已是 DISARMED，而 PRODUCT_CMD_DISARM 会在同一 handler 内从 DISARMING 直接转 DISARMED 并返回 COMPLETED。需先获用户批准异步 ACK/公共契约变更，再实现真实回执驱动闭环，之后补本项目 Host MIL 端到端断言 |
| FMAT-0014 | IN_PROGRESS | Host 时间服务核心证据与板级 TIM2、真实 UART/DMA、sensor_gnss_poll 全链路证据分开记录；P-10 overall 保持 PARTIAL |
| FMAT-0015 | FIXED_WAITING_RETEST | 上游数组边界修复及结构化边界测试需随当前固件基线回归确认 |
| FMAT-0016 / 0017 | VERIFIED（Issue 仍 Open） | 归档分类和 P-10b 数字对账已有历史证据；当前 main 完整复测后再按关闭清单结案 |
| FMAT-0018 | BLOCKED | Flight/main 比旧 MATLAB 基线前进 618 个提交，契约头/OSQP 锁已更新；GroundStopCertificate 被纳入 registry/ABI inventory（144/993），但 abi_arm/host/compare 仍是旧 143/986、55 messages，当前编译证据不同步。需重跑 ABI 工具并独立审查 revision policy；当前 Flight_Matlab main MATLAB 复测也未执行 |
| FMAT-0019 | FIXED_WAITING_RETEST | M6 汇总 solved/rejected 现必须与逐 job outcome 数量一致，covered_us 必须等于 solved×20,000 us，job ID 必须完整连续 1..N；新增三项负向夹具，等待 MATLAB 本地执行 |

因此，本轮 component_checks.json 仍可能因 FMAT-0012 的 coverage_90 返回 FAIL。这是当前未解决的验收合同问题，不代表可以跳过 M6，也不应通过修改门槛来消除。plant_open_loop_report.json.status=PARTIAL 和 P-10 overall PARTIAL 是当前设计边界的如实记录。

### FMAT-0018 的独立 ABI 验证

正常情况下，tools/run_local_validation.ps1 已在 MATLAB 证据归档之后自动运行 ARM/Host ABI 检查，并把新证据打包进 RUN_ID_ABI.zip。无需再次手工运行。

只有总包显示 ABI 为 SKIPPED_TOOLCHAIN_MISSING 时，才需要补齐 ARM/Host 工具链后重新运行一键脚本。工具链路径不同，使用第 3.3 节的带参数命令。

ABI 命令的固定规则：不得添加 --emit-lock，不得手工改 abi_lock.h 或 Product/Port revision。预期应明确显示 144 public types、993 fields、56/56 message registry，ARM 与 Host 证据来自同一轮运行，ABI lock 和 spec layout 检查 PASS。若不是该结果，保留报告交回；不要用旧的 143/986、55-message 报告关闭 FMAT-0018。即使该命令通过，Product/Port revision 是否保持 0x00010906 仍需独立审查结论。

implementation_manifest.json 当前仍是旧证据，不能作为本轮交付 PASS。只有 input_preflight、flight_entries、cold_start_report 为 PASS，Plant 为 PARTIAL、component_checks 为 PARTIAL_PASS 且 M6/P-10b gate 通过后，才可运行 tools/write_implementation_manifest.py 生成 PARTIAL_PASS_HOST_SIL 清单；它不是本轮必须单独发送的文件。

## 8. 验收方收到文件后会做什么

1. 校验 ZIP SHA-256、RUN_ID、run_manifest.json、两个仓库 commit 和所有源/产物指纹。
2. 核对同一 RUN_ID 下所有报告是否齐全、是否有旧报告混入、是否与被测 commit 一致。
3. 逐项复核失败报告、MATLAB Diary、模型结果和测试断言。
4. 对每个独立根因创建/更新 GitHub Issue，按优先级修复代码和文档。
5. 提交到 main，同步更新 SPEC、实施状态和下一轮本地验证交接。
6. 明确给出下一次运行命令、预期报告和需要交付的文件。

---

相关规范：

- [MATLAB 仿真测试数据集与验收标准](../MATLAB-验收与结果提交.md)
- [问题闭环规范](../quality/ISSUE_WORKFLOW.md)
- [问题关闭清单](../quality/ISSUE_CLOSURE_CHECKLIST.md)
- [下一阶段交付清单](next-phase-delivery.md)
- [项目 README](../../README.md)
