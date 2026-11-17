# MikuPet — 初音未来桌宠

macOS 原生 AppKit 桌宠：无边框透明置顶窗口 + 呼吸/眨眼/眼神跟随鼠标，
点她一下可以对话，并替你执行 Mac 操作、查家庭运维状态、下提醒和番茄钟。

纯系统框架，无第三方依赖，无联网自建服务（对话走本机 magpie 网关）。

## 快速开始

```bash
cd miku-pet
bash build.sh                 # 产出 MikuPet.app
open MikuPet.app              # 桌面右下角出现初音
```

点桌宠（或菜单栏小图标 →「打开对话面板」）即可对话。

## 指令能力

| 类别 | 说法示例 | 实现 |
|---|---|---|
| 对话问答 | 随便聊 | 本机网关 `127.0.0.1:3425`，模型 `group/never-stuck`，免鉴权 |
| 家庭运维速查 | 「磁盘还剩多少」「NAS 状态」 | SSH 免密到 NAS 跑只读命令，结果注入系统提示词 |
| Mac 系统操作 | 「打开 Safari」「音量调小」「锁屏」 | 白名单 `open` / `osascript` / `pmset` |
| 生活提醒 + 番茄钟 | 「提醒我 18:30 买菜」「番茄钟 25 分钟」 | `UNUserNotificationCenter` + 本地状态持久化 |

模型回复里带指令标记时本地执行，标记形式：

```
[[open:Safari]] [[volume:down]] [[lock]] [[sleep]]
[[pomodoro:25]] [[pomodoro_stop]] [[remind:2026-11-17 18:30 记得买菜]]
[[hide]] [[quit]]
```

## 目录

```
main.swift            入口 + 指令路由 + 菜单栏
PetView/PetView.swift 桌宠窗口内容（layer 树、动画、气泡）
UI/PetPanel.swift     对话面板
Core/                 ChatClient / NASStatus / Actions / TaskTimer / ReminderParser / SystemPrompt
assets/               base.png（闭眼底图 516×838 @2x）+ eyeL/eyeR.png（睁眼层，羽化 alpha）
tools/                图片处理与自检工具（见下）
build.sh              编译 + 打包 .app + ad-hoc 签名
```

## 自检工具（不需要录屏权限）

`screencapture` 在没有「屏幕录制」授权时只会报 `could not create image from display`，
所以这个项目用两条不依赖它的验证路径：

```bash
# 1) 把 PetView 的 layer 树离屏渲染成 PNG，直接看画出来没有
swiftc -O tools/render_test/main.swift PetView/PetView.swift -o tools/rt
./tools/rt /tmp/render.png open          # 睁眼；closed = 闭眼；再加 "bubble" 看气泡

# 2) 枚举窗口元数据，确认窗口真在屏幕上、尺寸/层级/alpha 对不对
swiftc -O tools/winspec.swift -o tools/winspec
./tools/winspec $(pgrep -f 'MikuPet.app/Contents/MacOS/MikuPet' | head -1)

# 3) 不开界面跑通指令链路（LLM → 指令解析 → 时间解析 → NAS 状态）
swiftc -O tools/functest/main.swift Core/ChatClient.swift Core/NASStatus.swift \
  Core/Actions.swift Core/ReminderParser.swift Core/SystemPrompt.swift -o tools/ft
./tools/ft "打开 Safari" "提醒我 18:30 记得买菜" "磁盘还剩多少"
```

图片标定工具：`crop`（按 top-left 裁剪）、`map`（把区域按颜色分类打成 ASCII，用来精确量眼睛边界）、
`prep2`（生成闭眼底图）、`eyes2`（切睁眼层）。

## 素材是怎么来的

原图是白底立绘，直接抠图会把她的白衬衫/脸一起弄穿（她本身就是白+青，和白底同色）。
最终链路：

1. 边缘连通洪水填充去背景（只从图片边框往里灌「近白」， enclosed 白块只在「又大又亮」时才清），
   保住衣服和皮肤。
2. 用 `map` 量出两只眼睛的像素中心/半径，**不靠目测网格**。
3. `prep2`：把眼白+虹膜按「上下眼睑带中位数 → 纵向渐变」填回肤色，保留原睫毛线 —— 天然就是一条闭眼线。
4. `eyes2`：从原图切出睁眼区域，做椭圆 smoothstep 羽化，作为「睁眼层」叠在底图上。

眨眼 = 睁眼层压扁+淡出，露出底图的闭眼线。

## 内存

RSS 约 90MB（面板/菜单栏/通知全开的打包版；裸二进制约 63MB）。
macOS 上一个最小 AppKit 程序就有 ~55MB 框架基线，图片资产只占几 MB，
换 ObjC 或继续压图都省不出多少，所以把精力放在功能上。

## 已知边界

- 对话依赖本机 magpie 网关在跑；网关不通时面板会明确报错，不会静默。
- NAS 状态查询走 SSH（`start@100.89.46.63:44`，密钥 `~/.ssh/id_ed25519`），结果缓存 60 秒。
- 「开机自启」用 `SMAppService`（macOS 14+），在菜单栏里开关；
  之前尝试手写 LaunchAgent 时 `launchctl load/bootstrap` 都报 `Input/output error`，未走通。
- 提醒/番茄钟依赖 `.app` bundle（裸可执行文件没有 bundle id，`UNUserNotificationCenter` 会崩）。
