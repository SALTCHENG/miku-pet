# MikuPet — 初音未来桌宠（macOS）

一个会走路、会爬屏幕边、会下落、能听懂话的小桌宠。无边框透明浮窗、不占 Dock、
高度只有屏幕的 ~13%（约 122pt），参考 shimeji 的行为模式。

## 快速开始

```bash
bash build.sh
open MikuPet.app
```

右键（或点一下）桌宠出输入面板；菜单栏也有同名图标。
输入面板里直接说话即可，例如「NAS 还剩多少磁盘」「提醒我 18:30 买菜」「打开 Safari」。

## 它能做什么

- **对话问答**：走本机 magpie 网关（`127.0.0.1:3425`，`group/never-stuck` 路由组，免鉴权）。
- **家庭运维速查**：NAS 磁盘/内存/温度等，SSH 到 NAS 取真实数据，缓存 60 秒。
- **Mac 系统操作**：打开应用、音量、锁屏、休眠、隐藏桌宠——模型回复里带 `[[open:Safari]]`
  这类指令标记，本地解析执行（白名单在 `Core/Actions.swift`，不会执行任意命令）。
- **提醒 + 番茄钟**：`[[remind:...]]` 解析成绝对时间，弹系统通知（未授权时自动降级为
  桌宠气泡+提示音）；`[[pomodoro:25]]` 开专注计时。

## 行为引擎（Core/Mover.swift）

60fps 心跳推进一个小状态机：待机 → 随机决定走/爬边/原地跳，走到屏幕左右边就攀爬，
从顶上松手会下落，落地有挤压回弹，拖拽松手按速度甩出去。纯数学，不读任何 IO。
无头仿真自测（240 秒）断言三条不变量：不穿地面、不越出屏幕、各阶段都能到达：

```bash
swiftc -O tools/moversim/main.swift Core/Mover.swift -o /tmp/moversim && /tmp/moversim
```

## 渲染（PetView/PetView.swift）

- 素材：`assets/anim/` 40 帧透明 PNG（385×310，idle 12 / walk 8 / climb 8 / fall 6 / drag 6）。
  完整身体：双马尾、双腿、脚都在画布内（v1 用被裁切的立绘硬缩放，才出现「头发缺失、
  腿只有一半」）。
- 朝向：朝左时用 `transform.scale(x:-1)` 镜像，按每帧内容中心比例（`centerRatio`）补偿，
  转身不横跳。
- 锚点在脚底：弹跳/倾斜绕脚转，脚精确贴地。
- 程序化动效代替眼球贴图：走路弹跳+侧倾、攀爬摆动、下落前倾、待机呼吸微摆，
  偶尔自动点头（比「眼珠跟着鼠标转」自然）。
- 帧动画用 `CAKeyframeAnimation(contents)` + `.discrete`；同时把第一帧写进 model layer，
  因为 `layer.render(in:)` 和「系统关掉动画」的场合只读 model 值。

## 自测

```bash
# 1) 离屏渲染各动作（不需要录屏权限，layer.render 出 PNG 直接目检）
swiftc -O tools/render_test/main.swift Core/*.swift PetView/PetView.swift -o tools/rt
./tools/rt /tmp/idle.png assets/anim idle
./tools/rt /tmp/walk.png assets/anim walk left

# 2) 窗口元数据（确认在屏、尺寸、层级）
swiftc -O tools/winspec.swift -o /tmp/winspec && /tmp/winspec

# 3) 指令链路端到端：打开面板输入或环境变量注入
MIKU_SELFTEST_ASK='打开 Safari|音量调大|提醒我 3 分钟后喝水' MikuPet.app/Contents/MacOS/MikuPet
```

## 内存

打包版稳态 RSS 约 **20MB**（启动头一分钟 60~75MB 是 dyld+PNG 解码的一次性开销，会回落）。
素材只 4.5MB、40 帧常驻；`Core/Sprites.swift` 里按动作族设了抽稀上限（idle≤12 等），
116 帧全量解码那种「图多就是好」的做法对桌宠没必要。

## 已知边界

- 对话依赖本机 magpie 网关在跑；网关不通时面板会明确报错，不会静默。
- NAS 状态查询走 SSH（`start@100.89.46.63:44`，密钥 `~/.ssh/id_ed25519`），结果缓存 60 秒。
- 提醒/番茄钟依赖 `.app` bundle（裸可执行文件没有 bundle id，`UNUserNotificationCenter` 会崩）。
- 本机通知授权目前是「拒绝」状态（系统设置里可能锁死），代码已兜底：未授权就桌宠气泡+声音。
- 「打开应用」依赖模型输出英文 App 名；说「打开计算器」这类不常用应用，模型偶尔会不发
  标记只口头答应 —— 提示词已强调（`Core/SystemPrompt.swift` 第 5/6 条），仍非 100%。
  确定性命令（提醒/番茄钟/锁屏/隐藏/退出）已在 `main.swift` 的 `localCommand` 走本地快路径绕开 LLM；
  **音量还没进这条快路径**，所以「音量调大」偶尔会漏标记。
