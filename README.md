# 头文字D 追逐战系统 - 实现指南

## 概述
本文档旨在指导开发人员（或 AI）为《Assetto Corsa》实现一个类似“头文字D”风格的追逐战系统。该系统由用于比赛管理的服务器端插件和用于视觉效果与本地逻辑的客户端 Lua 脚本组成。

## 目标
建立一个系统，允许两名玩家进行“猫鼠游戏”式的山路追逐战。追逐者必须在比赛结束前保持在领跑者一定距离内，或者超越领跑者才能获胜。

## 架构

```mermaid
graph TD
    ClientA[玩家 A (客户端)] <-->|Lua 脚本视觉效果| ClientA_Lua
    ClientB[玩家 B (客户端)] <-->|Lua 脚本视觉效果| ClientB_Lua
    Server[AssettoServer] <-->|插件逻辑| ChasePlugin
    ChasePlugin -- "指令 / 状态更新" --> ClientA
    ChasePlugin -- "指令 / 状态更新" --> ClientB
```

## 1. 服务端插件 (C#)

服务端插件负责管理游戏状态、处理指令以及广播开始/结束事件。

### 前置条件
- .NET 6.0 (或与 AssettoServer 版本匹配)
- AssettoServer SDK 引用

### 文件结构
```
ChaseBattlePlugin/
├── ChaseBattlePlugin.csproj
├── ChaseBattle.cs
├── ChaseCommands.cs
└── ChaseConfiguration.cs
```

### 参考实现

#### ChaseBattlePlugin.csproj
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net6.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="AssettoServer.Shared" />
    <Reference Include="AssettoServer" />
    <!-- 添加其他必要的引用 -->
  </ItemGroup>
</Project>
```

#### ChaseCommands.cs
```csharp
using AssettoServer.Commands;
using AssettoServer.Server;
using Qmmands;

public class ChaseCommands : ACModuleBase
{
    private readonly ChaseBattle _service;

    public ChaseCommands(ChaseBattle service)
    {
        _service = service;
    }

    [Command("chase")]
    public void StartChase(ACClient target)
    {
        // ACClient 代表发起指令的玩家
        // 发起挑战给 'target' 的逻辑
        _service.InitiateChallenge(Context.Client, target);
    }
}
```

#### ChaseBattle.cs
```csharp
using AssettoServer.Server;
using AssettoServer.Server.Plugin;
using Microsoft.Extensions.Hosting;

public class ChaseBattle : BackgroundService
{
    private readonly ACServer _server;
    // 状态: 等待中 (Waiting), 倒计时 (Countdown), 进行中 (Active), 已结束 (Finished)
    
    public ChaseBattle(ACServer server)
    {
        _server = server;
    }

    public void InitiateChallenge(ACClient challenger, ACClient target)
    {
        // 1. 验证玩家 (距离, 车型)
        // 2. 发送请求给目标 (通过聊天)
        // 3. 设置状态为 'Pending' (待处理)
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            // 主游戏循环 (例如: 10Hz)
            // 1. 检查参与者之间的距离
            // 2. 通过聊天或自定义数据包向客户端广播距离/差距
            // 3. 检查胜利条件 (超越, 差距 > 最大值, 差距 < 最小值)
            
            await Task.Delay(100, stoppingToken);
        }
    }
}
```

## 2. 客户端脚本 (Lua)

客户端脚本负责渲染 UI (进度条, 文字) 并且可以处理一些本地逻辑 (例如：如果服务器延迟，本地检测超越，但最终以服务器为准)。

### 文件结构
```
apps/lua/chase_battle/
├── manifest.ini
└── chase_battle.lua
```

#### manifest.ini
```ini
[ABOUT]
NAME = Chase Battle
AUTHOR = AI Generator
VERSION = 1.0
DESCRIPTION = Initial D Style Chase Battle System
```

#### chase_battle.lua
```lua
local chaseMode = false
local opponentCarIndex = -1
local role = "none" -- "leader" (领跑) or "chaser" (追逐)

-- 监听服务器消息 (目前简化为聊天消息)
-- 在实际实现中，如果有自定义协议则使用自定义协议，或者解析聊天信息
function onChatMessage(message, sender)
    if message:find("CHASE_START") then
        local targetName = message:match("Target: (.+)")
        -- 通过名字查找车辆索引
        for i, c in ac.iterateCars() do 
            if c.driverName == targetName then
                opponentCarIndex = c.index
                chaseMode = true
            end
        end
    end
end

function script.update(dt)
    if not chaseMode or opponentCarIndex == -1 then return end

    local myCar = ac.getCar(0)
    local oppCar = ac.getCar(opponentCarIndex)

    local distance = (myCar.position - oppCar.position):length()
    
    -- 绘制 UI
    ui.beginTransparentWindow("chase_ui", vec2(100, 100), vec2(400, 200))
    ui.text("距离: " .. math.floor(distance) .. "米")
    
    -- 待办: 添加 "头文字D" 风格的转速表和紧张感进度条
    ui.endWindow()
end

## 3. 管理员面板 (Admin Panel)

为了方便管理员组织比赛，我们将开发一个侧边栏应用 (Sidebar App)。

### 功能设计
1.  **玩家列表**: 列出当期服务器内的所有玩家。
2.  **角色选择**: 每个玩家旁边有两个单选框或按钮：“领跑 (Leader)” 和 “追逐 (Chaser)”。
3.  **开始按钮**: 选中两人后，点击“开始比赛”按钮。
4.  **指令发送**: 插件将自动在聊天框输入指令（例如 ` /chase start <LeaderID> <ChaserID>`）并发送给服务端。

### Lua 实现思路
```lua
-- admin_panel.lua
local leaderIdx = -1
local chaserIdx = -1

function script.update(dt)
    ui.beginWindow("Chase Admin", vec2(200, 400))
    
    for i, car in ac.iterateCars() do
        ui.text(car.driverName)
        ui.sameLine()
        if ui.radioButton("Leader##"..i, leaderIdx == i) then leaderIdx = i end
        ui.sameLine()
        if ui.radioButton("Chaser##"..i, chaserIdx == i) then chaserIdx = i end
    end

    if ui.button("Start Chase Battle") then
        if leaderIdx ~= -1 and chaserIdx ~= -1 then
            -- 发送指令 (假设 acc-lua-sdk 支持 ac.sendChatMessage，如果不支持则需通过 ac.console 或其他方式交互)
            ac.sendChatMessage("/chase start " .. indexToSessionId(leaderIdx) .. " " .. indexToSessionId(chaserIdx))
            -- 注意：如果 SDK 不支持直接发送聊天，可能需要提示管理员手动输入，或使用 ac.console() 打印命令供复制
        end
    end
    
    ui.endWindow()
end
```

## 4. 结果回报与胜负判定 (Result & Adjudication)

鉴于山路环境的复杂性，自动判定可能存在误判。因此，我们采用 **"系统辅助 + 人工确认"** 的模式。

### 判定逻辑 (Adjudication Logic) - 混合模式 (Hybrid)

为了解决山路（蜿蜒曲折）带来的距离判定难题，我们采用 **"Spline 自动判定 + 人工复核"** 的混合模式。

1.  **自动判定 (Primary: Spline Based)**:
    *   **原理**: 利用 Assetto Corsa 的 `Spline Position` (赛道进度 0.0~1.0) 来计算两车沿赛道中心线的实际距离，而非直线距离。这完美解决了发卡弯中“直线距离近但实际赛道距离远”的问题。
    *   **公式**: `Distance = (Leader.Spline - Chaser.Spline) * TrackLength`
    *   **触发**: 当计算出的赛道距离连续 3 秒超过阈值（如 > 150m），系统自动判定胜负并广播。

2.  **人工复核 (Fallback: Manual)**:
    *   **触发条件**:
        *   当比赛在终点线结束且两车距离极其接近 (< 10m) 时（Photo Finish）。
        *   当系统检测到异常（如车辆严重切弯/掉出地图）导致 Spline 数据抖动时。
    *   **流程**: 系统不直接宣布胜者，而是提示 "Waiting for confirmation..."。车手需手动输入 `/claim` 或点击 UI 确认胜负。

3.  **最终裁决 (Override)**:
    *   无论系统如何判定，管理员更有最高权限，可随时使用 `/admin win` 修正结果。

### 比赛流程 (Game Flow) - 回合制 (Round Based)

为了还原《头文字D》经典规则，比赛通常分为多个回合：

1.  **第一回合 (Round 1)**: A 领跑，B 追逐。
    *   如果 B 超越 -> **B 胜 (Win)**。
    *   如果 A 甩开 (> 150m) -> **A 胜 (Win)**。
    *   如果 到达终点且距离 < 150m -> **平局 (Draw)，进入第二回合**。

2.  **换位重赛 (Swap & Replay)**:
    *   系统提示: "Round 1 Draw! Swapping Positions..."
    *   该机制要求玩家手动或通过 teleport 插件（如有）回到起点，并交换先行/后追顺序。
    *   **第二回合 (Round 2)**: B 领跑，A 追逐。判罚标准同上。

3.  **死亡胶着 (Sudden Death)**:
    *   如果两回合均为平局，则进入“死亡胶着”模式，通常是无尽的循环，直到一方轮胎耗尽或失误。

### 回报方式 (Reporting Methods)

#### 1. 全服公告 (Server Broadcast)
服务端通过聊天框向所有玩家广播最终结果。
*   格式: `🏁 [比赛结束] 胜者: {WinnerName} ({Reason})`
*   示例: `🏁 [比赛结束] 胜者: Takumi (原因: 对手承认失败)`

#### 2. 屏幕特效 (On-Screen Effects)
参赛玩家的屏幕上会出现巨大的 "WIN" 或 "LOSE" 字样。
*   **Lua 脚本**: 接收到服务端发送的 `CHASE_RESULT` 消息后，触发 UI 动画。
*   **动画效果**: 文字从屏幕中心弹出，保持 5 秒后消失。

#### 3. 管理员面板更新
管理员面板将显示上一场比赛的结果，并提供“重置”按钮以便开始下一场。

## 5. 视觉体验与 HUD 设计 (Visual Experience & HUD)

为了提升沉浸感（Immersive Experience），我们需要为参赛者和观众提供即时、关键的比赛信息。

### A. 参赛者视角 (Participants' View)

#### 1. 距离指示条 (Battle Distance Bar)
模仿格斗游戏血条的设计，置于屏幕顶部中央。
*   **设计**: 一条长条，中心为 "0m"（并排）。
    *   **左侧 (红)**: 追逐者缩短差距 (Danger Zone)。
    *   **右侧 (蓝)**: 领跑者拉大差距 (Safe Zone)。
    *   **阈值标记**: 在条上标记出 "胜负判定点" (例如 50m 和 150m)，让玩家直观看到距离胜利或失败还有多远。
*   **动画**: 当距离快速变化时，指示条会有高亮流动效果。

#### 2. 攻防状态 (Role Status)
在屏幕左下角显示当前角色图标。
*   **领跑者 (Leader)**: 显示 "先行 (Lead)" 图标，颜色为蓝色。重点数据：与后车距离 (Gap)。
*   **追逐者 (Chaser)**: 显示 "追击 (Chase)" 图标，颜色为红色。重点数据：与前车距离 (Delta)。

#### 3. 赛段进度 (Section Progress)
显示当前比赛进行的百分比，让车手知道距离终点还有多远，便于分配轮胎和进攻节奏。
*   **形式**: 屏幕底部的细长进度条，带有 "Start" 和 "Finish" 标记。

### B. 观众与直播视角 (Spectator & Broadcast View)

#### 1. 战斗卡片 (Battle Card)
屏幕左上角的常驻 UI，类似格斗游戏的角色板。
*   **[头像/车辆] vs [头像/车辆]**
*   **实时 Gap**: 显示大号数字 (例如 `+0.35s` 或 `12m`)。
*   **状态**: 只有当发生超越 (Overtake) 时，显示闪烁的 "OVERTAKE" 红色字样。

#### 2. 赛道地图 (Track Map)
屏幕右上角的小地图。
*   **高亮**: 仅高亮显示两名正在对决的玩家，其他玩家（观众）以半透明灰点显示或隐藏。
*   **领跑线**: 在地图上动态绘制领跑者轨迹，追逐者轨迹用不同颜色叠加，展示路线差异。

#### 3. 动态运镜 (Replay/Drone Cam)
*   **启用**: 当距离小于 20m 时，自动切换到更紧凑的追逐视角 (如果服务器允许强制视角)。
*   **慢动作**: 比赛结束瞬间，服务器记录时间戳，Lua 脚本尝试回放最后 5 秒的精彩镜头 (需本地回放 API 支持，若不支持则忽略)。

## 6. 远程部署与通信评估 (Deployment & Sync)

### 远程 Lua 加载 (CSP Remote Lua)
利用 CSP 的 `[EXTRA_TWEAKS] LUA_SCRIPT = ...` 功能，可以让客户端自动加载指定的 Lua 脚本，无需玩家手动安装。

#### 评估 (Evaluation)
*   **优点**:
    *   **零配置**: 玩家只需进入服务器，脚本自动运行。
    *   **版本统一**: 所有玩家强制使用同一版本的逻辑和 UI。
*   **挑战**:
    *   **单文件限制**: 通常只支持单一 Lua入口。这意味着我们需要将所有逻辑（UI, 网络, 游戏逻辑）打包到一个文件中，或者使用 `require` 动态加载网络资源（需 `ac.web` 支持）。
    *   **资源加载**: 图片、字体等资源无法随脚本直接下载。
*   **解决方案**:
    *   **代码打包**: 开发时分模块，发布时使用脚本将所有 Lua 文件合并为一个 `bundle.lua`。
    *   **在线资源**: 图片资源上传到图床或服务器 Web 目录，脚本运行时通过 `ac.web.download` 下载到临时缓存。
    *   **程序化绘图**: 尽量减少图片使用，使用 `ui.path` 绘制矢量图形（如进度条、背景框），以减少对外部资源的依赖。

### 通信协议 (Sync Protocol)
为了实现全服同步，我们尽量复用 Assetto Corsa 原生支持的通信渠道。

1.  **握手 (Handshake)**:
    *   客户端连接时，发送 `CHASE_CLIENT_VERSION`。
    *   服务端回复 `CHASE_SERVER_READY`。

2.  **状态同步 (State Sync)**:
    *   服务端以 2Hz - 5Hz 的频率广播 `CHASE_STATE` (包含: 阶段, 领跑者ID, 追逐者ID, 当前距离)。
    *   客户端根据 `CHASE_STATE` 更新 UI。

3.  **结果同步**:
    *   服务端广播 `CHASE_RESULT`。
    *   客户端展示结算动画。

### 通信命令结构 (Command Structure)

为了确保可靠性，使用以下聊天命令结构 (如果可能，隐藏命令):

1.  **挑战 (Challenge)**: `服务端 -> 目标`: "玩家 A 向您发起挑战! 输入 /accept 开始。"
2.  **开始 (Start)**: `服务端 -> 所有人`: "CHASE_START: [车手A] vs [车手B]"
3.  **更新 (Update)**: `服务端 -> 客户端`: (可选) "GAP: 5.2s" (每隔几秒广播一次)
4.  **结束 (Finish)**: `服务端 -> 所有人`: "WINNER: [车手A] (原因: 超越 / 甩开)"

## 7. 安装步骤 (Installation)

1.  **服务端**: 编译 C# 插件并将 DLL 放入 `AssettoServer/plugins/` 目录。
2.  **客户端**: 将 `chase_battle` 文件夹放入 `content/gui/apps/lua/` 或 `apps/lua/` (取决于安装方式)。
3.  **配置**: 在 `server_cfg.ini` 中启用插件 (如果 AssettoServer 需要)。

## 8. 后续开发计划 (Future Plans)

1.  完善 `ChaseBattle.cs` 以处理状态机 (待处理 -> 倒计时 -> 比赛中)。
2.  增强 `chase_battle.lua`，使用 `ac.getCarState` 获取更多遥测数据 (转速, 涡轮压力)。
3.  实现 "突然死亡" (Sudden Death) 机制 (如果差距在 X 秒内保持很小，延长比赛)。

## 9. 技术实现细节补充 (Technical Implementation Details)

### A. 传送机制 (Teleportation)
由于 Assetto Corsa 物理引擎的限制，直接修改车辆物理坐标较为困难。
我们计划尝试以下方案：
1.  **可视节点位移**: 使用 `ac.findNodes('carRoot:<Index>'):setPosition(pos)` 尝试移动车辆模型根节点。
2.  **重置回维修区 (Fallback)**: 如果直接传送导致物理异常，将使用 `Reset to Pits` 命令（通过 Server 插件或 `ac.console`）。

### B. 油门锁定 (Throttle Locking)
利用 CSP 的 `Extra Tweaks` 远程加载 Lua 脚本功能，注入控制覆盖逻辑。
*   **API**: `ac.overrideCarState(key, value)`
*   **逻辑**: 当玩家被判定为“非参赛状态”时，脚本每帧调用：
    ```lua
    ac.overrideCarState('gas', 0)
    ac.overrideCarState('brake', 1)
    ac.overrideCarState('steer', 0)
    ```
*   **解锁**: 比赛开始或倒计时结束时，停止调用 override 函数。
