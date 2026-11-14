# MATLAB 本地验证交接说明

版本：1.0  
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

本项目 MATLAB Project 文件在仓库中实际命名为 Flight_Matalab.prj（历史拼写如此，暂不重命名）。请从 Flight_Matlab 仓库根目录打开该文件。

### 2.2 已知验证环境基线

| 项目 | 基线/要求 |
|---|---|
| 操作系统 | Windows 10/11 x64 |
| MATLAB | R2026b Update 1（既有证据环境；其他版本需单独记录） |
| Simulink | 与 MATLAB 同版本 |
| PowerShell | PowerShell 7，命令名 pwsh |
| Host SIL 编译器 | MinGW-w64 GCC；默认 D:\STM32CubeCLT\mingw64\bin |
| MATLAB MEX 编译器 | MATLAB 支持的 C 编译器，先执行 mex -setup C |
| ABI ARM 编译器（仅 FMAT-0018） | GNU Arm Embedded；默认 D:\\STM32CubeCLT\\GNU-tools-for-STM32\\bin |
| Python | Python 3，可执行 python |
| 上游仓库 | 同级 Flight，commit 必须满足 config/flight_baseline.json 与 external_dependencies.lock.json |

如果编译器安装目录不同，后续 MATLAB 命令使用 run_component_checks('你的MinGW目录')。不要因为预检 Hash 不匹配而手工改锁文件；先核对 Flight commit 和路径。

## 3. 拉取两个仓库 main 与上游基线准备

在 PowerShell 中进入本项目根目录后执行：

~~~powershell
git fetch origin --prune
git switch main
git pull --ff-only origin main

git -C ..\Flight fetch origin --prune
git -C ..\Flight switch main
git -C ..\Flight pull --ff-only origin main

git branch --show-current
git rev-parse HEAD
git status --short

git -C ..\Flight rev-parse HEAD
git -C ..\Flight branch --show-current
git -C ..\Flight status --short
~~~

检查要求：

- git branch --show-current 必须输出 main。
- git status --short 如果显示本地修改，先保留并报告；不要执行 git reset --hard、git clean 或覆盖模型/字典/录制文件。
- 首次同步后不要先单独运行 python -B tools\verify_inputs.py：旧 config/flight_baseline.json 会在 Host SIL 构建时由当前 Flight 源文件重新生成。
- 标准 run_component_checks 顺序为：重建同级 Flight Host SIL → record_flight_baseline.py 重新记录当前源文件 → build_native_kernels 内部运行 verify_inputs.py → 预检 PASS 后才继续 MEX、模型和组件验收。
- 如果只想单独诊断依赖预检，可先运行 pwsh -NoProfile -File .\tools\build_flight_runtime.ps1 -GccDir 'D:\STM32CubeCLT\mingw64\bin'，再运行 python -B .\tools\verify_inputs.py。正式完整验收不需要重复手工构建。
- 预检失败时保留 work\validation\input_preflight.json 和完整 Diary，并把归档交回；不得手工修改基线或锁文件绕过失败。
- 记录 Flight_Matlab 与 Flight 两个仓库的完整 HEAD SHA。归档脚本也会记录这两个 commit。

## 4. MATLAB 完整验证（唯一标准入口）

### 4.1 打开工程

1. 启动 MATLAB。
2. 将当前目录切换到 Flight_Matlab 仓库根目录。
3. 打开 Flight_Matalab.prj。
4. 在 MATLAB 命令窗口执行 mex -setup C，确认 C 编译器可用。

### 4.2 执行完整验收

推荐直接复制以下命令。它会保存完整 Diary；即使测试报错，也会先关闭 Diary 再抛出错误。

~~~matlab
root = flight_startup;
reportDir = fullfile(root, 'work', 'validation');
if ~isfolder(reportDir)
    mkdir(reportDir);
end

diaryFile = fullfile(reportDir, 'matlab_acceptance_diary.txt');
diary(diaryFile);
diary on;

try
    run_component_checks('D:\STM32CubeCLT\mingw64\bin');
catch ME
    disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    diary off;
    rethrow(ME);
end

diary off;
~~~

如果 MinGW 使用默认路径，也可以执行 run_component_checks。

完整入口会自动：

1. 重建同级 Flight 的 Windows Host SIL 运行库。
2. 重建本项目 MEX；build_native_kernels 会重新执行 verify_inputs.py，input_preflight.json 必须为 PASS，且会登记到 component_checks.checks.input_preflight。
3. 重建参数字典、Plant、Flight、PID/Actuation 模型。
4. 运行 26 s 默认 MIL 闭环并刷新 DataSIM、ExtINS DataSIM 回放。
5. 运行 M6 job 证据完整性、OSQP、Plant、传感器事件队列、TimeService、GNSS、RECTIMEA、真值隔离、PID 和执行器等组件 gate。
6. 生成当前运行的 JSON 报告、源码指纹、模型/字典/MEX/录制文件指纹及运行前后 Git 状态。

不要用单独的 verify_flight_entries 或单个 Plant 测试代替完整验收。单项调试可以额外执行，但正式交付仍需完整入口。

## 5. 生成不可覆盖的验证归档

MATLAB 命令结束后，确认 Diary 已关闭，再回到 PowerShell 的仓库根目录执行：

~~~powershell
pwsh -NoProfile -File .\tools\archive_validation_run.ps1
~~~

成功后会输出：

- 唯一 RUN_ID，格式为 YYYYMMDDTHHMMSSfffZ_<commit-short>；
- work/validation/archives/RUN_ID/ 归档目录；
- work/validation/archives/RUN_ID.zip；
- work/validation/archives/RUN_ID.zip.sha256。

归档包含本轮 JSON 报告、MATLAB Diary、源码/产物指纹、运行前后 Git 状态、生成资产分类、run_manifest.json 和本轮 scenarios/flight_sil_recording.mat 副本。模型、字典和 MEX 的文件哈希会登记在 artifact fingerprint；默认不把所有 .slx/.sldd 二进制文件重复塞入 ZIP。

重要：归档成功后脚本会清空 work/validation/ 当前层的临时报告，历史 archives/ 不会删除。每个 RUN_ID 不可覆盖。一个运行完成后立即归档，再开始下一轮；不要在归档前重复运行完整入口，以免混淆证据。

如果归档命令失败：

- 不要删除或清理 work/validation/；
- 保留完整 MATLAB Diary 和 PowerShell 错误；
- 将整个 work/validation/ 文件夹打包交回，或至少交回 component_checks.json、input_preflight.json、flight_entries.json、m6_report.json、plant_open_loop_report.json、current_source_fingerprint.json、current_artifact_fingerprint.json、git_state_before.json、git_state_after.json 和 Diary。

## 6. 必须交付给验收方的文件与信息

### 6.1 每次完整运行的必交文件

| 文件/信息 | 必须 | 用途 |
|---|---|---|
| RUN_ID.zip | 是 | 本轮完整证据包 |
| RUN_ID.zip.sha256 | 是 | 校验 ZIP 未损坏或被替换 |
| config/flight_baseline.json | 若本轮重建后发生变化则必须单独交付 | 由当前 Flight/main Host SIL 构建重新生成；ZIP 只保存指纹不保存该源码文件。交给验收方审查后提交 main，不要自行提交 |
| RUN_ID | 是 | 关联报告与问题记录 |
| Flight_Matlab 完整 commit SHA | 是 | 确认被测源码 |
| Flight 完整 commit SHA | 是 | 确认固件上游基线 |
| MATLAB Release、Windows 版本 | 是 | 确认运行环境 |
| GCC 路径/版本及 MEX 编译器 | 是 | 定位构建差异 |
| component_checks.json 顶层状态 | 是 | 快速判断本轮 PASS/FAIL/PARTIAL_PASS |

ZIP 正常时，不需要再单独发送 ZIP 内已有的每一份 JSON 或 MAT 文件。唯一例外是本轮重建后发生变化的 config/flight_baseline.json：它是需要纳入 Git 的配套源码基线，必须另行交付给验收方审查。

### 6.2 需要额外发送的文件

- 如果 generated_assets.json 显示本轮修改了某个原先已存在的模型/字典，且问题与该模型/字典有关，再按要求额外提供对应 .slx 或 .sldd 文件。
- 如果 component_checks 在归档前中断，发送第 5 节列出的原始报告和完整 Diary。
- 对 FMAT-0018，先完成并归档 MATLAB 运行，再在 Flight 仓库根目录运行 `python -B tests\\abi\\abi_report.py --arm-bin D:\\STM32CubeCLT\\GNU-tools-for-STM32\\bin --host-bin D:\\STM32CubeCLT\\mingw64\\bin`（不要加 `--emit-lock`）。额外交付完整终端输出及 `tests/abi/evidence/abi_arm.json`、`abi_host.json`、`abi_compare.json`、`abi_report.md`、`commands.json`、`artifact_sha256.json`、`abi_probe.c`、`abi_canonical_arm.txt`、`abi_canonical_host.txt`。这组 ABI 证据不包含在 Flight_Matlab 的 MATLAB ZIP 中。该命令会改写 Flight 工作区中的证据文件；完成后先不要启动下一轮 MATLAB，也不要提交 abi_lock/revision 修改，等独立审查确认后再处理。
- 截图只能辅助定位，不能替代报告、日志、数据文件和 SHA-256。

## 7. 如何登记 MATLAB 发现的问题

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

## 8. 本轮已知问题与结果解释

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

### FMAT-0018 的独立 ABI 验证（与 MATLAB 完整运行分开）

在同级 Flight 仓库切换并同步 main 后，从 Flight 根目录执行：

~~~powershell
python -B tests\abi\abi_report.py
~~~

不要添加 `--emit-lock`，不要手工改 abi_lock.h 或 Product/Port revision。该命令会刷新 ARM/Host 编译证据、比较报告和 artifact SHA 清单，并对当前 abi_lock 做校验。预期应明确显示 144 public types、993 fields、56/56 message registry，ARM 与 Host 证据来自同一轮运行，ABI lock 和 spec layout 检查 PASS。若不是该结果，保留完整终端输出及生成的 evidence 文件并交回；不要用旧的 143/986、55-message 报告关闭 FMAT-0018。即使该命令通过，Product/Port revision 是否保持 0x00010906 仍需独立审查结论。

implementation_manifest.json 当前仍是旧证据，不能作为本轮交付 PASS。只有 input_preflight、flight_entries、cold_start_report 为 PASS，Plant 为 PARTIAL、component_checks 为 PARTIAL_PASS 且 M6/P-10b gate 通过后，才可运行 tools/write_implementation_manifest.py 生成 PARTIAL_PASS_HOST_SIL 清单；它不是本轮必须单独发送的文件。

## 9. 验收方收到文件后会做什么

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
