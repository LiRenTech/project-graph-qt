# Godot MCP Native (模型上下文协议)

[English Version](https://github.com/yurineko73/Godot-MCP-Native/blob/main/README.md)

![Godot 版本](https://img.shields.io/badge/Godot-4.x-blue?logo=godot-engine)
![许可证](https://img.shields.io/badge/License-MIT-green)
![版本](https://img.shields.io/badge/Version-1.0.8-brightgreen)

一个强大的 Godot 引擎插件，通过模型上下文协议 (MCP) 集成 AI 助手（如 Claude 等）。让 AI 可以直接通过自然语言读取和修改您的 Godot 项目——场景、脚本、节点和资源。

## 🚀 功能特性

- **完整项目访问**：AI 助手可以读取和修改脚本、场景、节点和资源
- **原生实现**：无需 Node.js 依赖——完全在 Godot 中运行
- **实时编辑**：直接在编辑器中应用 AI 建议
- **全面的工具集**（155 个工具——30 核心 + 125 补充）：
  - **节点工具**（9 核心 + 11 高级）：创建、修改、管理场景节点，复制、移动、重命名，锚点预设，信号连接，组管理，批量操作，场景审计
  - **脚本工具**（7 核心 + 8 高级）：编辑、分析、创建、附加、验证 GDScript 和 C# 文件，执行脚本，文件搜索，符号索引，定义和引用查找
  - **场景工具**（4 核心 + 4 高级）：操作场景结构、保存场景、列出/打开/关闭场景标签页，项目场景列表
  - **编辑器工具**（4 核心 + 12 高级）：控制编辑器功能、截图、信号检查、文件系统重载，节点/文件选择，导出管理，属性检查器
  - **调试工具**（3 核心 + 68 高级）：日志、调试会话、断点、栈帧/变量读取、性能分析器、运行时探针，动画/音频/着色器/瓦片地图运行时控制，调试执行控制，场景就绪等待
  - **项目工具**（3 核心 + 23 高级）：访问项目设置、列出资源、创建资源，运行测试、管理输入映射、检查自动加载/全局类，资源诊断与健康审计

## 🖥️ gdmcp CLI

本插件包含配套的 **gdmcp CLI**，供编程代理（Codex、Claude Code 等）使用，
相比 MCP 可减少约 30,000 tokens 的上下文消耗。在 MCP 停靠面板的 **CLI Tools** 标签页中安装，
或从 [GitHub Releases](https://github.com/yurineko73/Godot-MCP-Native/releases) 下载。

详见 [CLI README](https://github.com/yurineko73/Godot-MCP-Native/blob/main/cli/gdmcp/README.md)。

## 📦 安装

### 方法 1：资源库（推荐）
1. 打开您的 Godot 项目
2. 进入编辑器中的 **AssetLib** 标签页
3. 搜索 "Godot MCP Native"
4. 点击 **下载** 然后 **安装**

### 方法 2：手动安装
1. 下载或克隆此仓库
2. 将 `addons/godot_mcp` 文件夹复制到项目的 `addons/` 目录
3. 在 Godot 中打开项目
4. 进入 **项目 > 项目设置 > 插件**
5. 启用 "Godot MCP Native" 插件

## 🔧 使用

### 启用插件
1. 打开 **项目 > 项目设置 > 插件**
2. 在列表中找到 "Godot MCP Native"
3. 将状态设置为 **启用**

### 配置 MCP 服务器
插件提供两种传输模式：

#### HTTP 模式（用于远程访问）
- 适用场景：基于网络的 AI 集成
- 配置：在插件设置中设置 `transport_mode = "http"` 并配置 `http_port`（默认：9080）
- 可选：启用 `auth_enabled` 并设置 `auth_token` 以保障安全

### 连接 Claude Desktop

首先安装 `mcp-remote` 包：
```bash
npm install mcp-remote
```

#### HTTP 模式配置
```json
{
  "mcpServers": {
    "godot-mcp": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://localhost:9080/mcp"
      ]
    }
  }
}
```

### 连接 Cursor / Trae

#### HTTP 模式配置

```json
{
  "mcpServers": {
    "godot-mcp": {
      "url": "http://localhost:9080/mcp"
    }
  }
}
```

带身份验证：
```json
{
  "mcpServers": {
    "godot-mcp": {
      "url": "http://localhost:9080/mcp",
      "headers": {
        "Authorization": "Bearer your-secret-token-here"
      }
    }
  }
}
```

### 连接 Cline

#### HTTP 模式配置
编辑 Cline 配置文件（`cline_mcp_settings.json`）：

```json
{
  "mcpServers": {
    "godot-mcp": {
      "url": "http://localhost:9080/mcp",
      "type": "streamableHttp",
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

### 连接 OpenCode

#### HTTP 模式配置

```json
{
  "mcp": {
    "godot-mcp": {
      "type": "remote",
      "url": "http://localhost:9080/mcp"
    }
  }
}
```

### 连接 Codex

#### HTTP 模式配置

```toml
[mcp_servers]

[mcp_servers.godot-mcp]
type = "streamableHttp"
url = "http://localhost:9080/mcp"
```

## 💬 示例提示

连接后，您可以通过 Claude 与 Godot 项目交互：

```
@mcp godot-mcp read godot://script/current

我需要帮助优化我的玩家移动代码。能提出改进建议吗？
```

```
@mcp godot-mcp get-scene-tree

在场景中间添加一个立方体，并创建一个相机看向它。
```

```
创建一个主菜单，包含开始、选项和退出按钮
```

```
实现一个带有动态光照的昼夜循环系统
```

## 📚 可用命令

### Node-Write (6)
- `create-node` - 创建新节点
- `delete-node` - 删除节点
- `update-node-property` - 更新节点属性
- `duplicate-node` - 复制节点及子节点
- `move-node` - 移动节点到新父节点
- `rename-node` - 重命名节点

### Node-Read (3)
- `get-scene-tree` - 获取场景树结构
- `get-node-properties` - 获取特定节点的属性
- `list-nodes` - 列出父节点下的所有节点

### Node-Write-Advanced (5)
- `set-anchor-preset` - 设置 Control 节点锚点预设
- `connect-signal` - 连接节点间的信号
- `disconnect-signal` - 断开信号连接
- `set-node-groups` - 设置节点的组成员关系
- `add-resource` - 向节点添加资源子节点（碰撞形状、网格等）

### Node-Advanced (6)
- `get-node-groups` - 获取节点所属的组
- `find-nodes-in-group` - 查找组中的所有节点
- `batch-update-node-properties` - 在单个 UndoRedo 动作中批量更新节点属性
- `batch-scene-node-edits` - 在单个 UndoRedo 动作中批量执行场景节点编辑
- `audit-scene-node-persistence` - 审计节点 owner 和持久化状态
- `audit-scene-inheritance` - 审计场景继承/实例化结构

### Script (7)
- `list-project-scripts` - 列出所有脚本
- `read-script` - 读取特定脚本
- `modify-script` - 更新脚本内容
- `create-script` - 创建新脚本
- `get-current-script` - 获取当前正在编辑的脚本
- `attach-script` - 将已有脚本附加到节点
- `execute-script` - 执行 GDScript 表达式

### Script-Advanced (8)
- `analyze-script` - 分析脚本结构
- `validate-script` - 验证 GDScript 语法
- `search-in-files` - 搜索项目文件
- `list-project-script-symbols` - 索引 GDScript 和 C# 文件的脚本符号
- `find-script-symbol-definition` - 查找脚本符号的定义位置
- `find-script-symbol-references` - 查找脚本符号的文本引用
- `rename-script-symbol` - 跨文件重命名脚本符号
- `open-script-at-line` - 在编辑器中打开脚本到指定行

### Scene (4)
- `create-scene` - 创建新场景
- `save-scene` - 保存当前场景
- `open-scene` - 打开场景
- `get-current-scene` - 获取当前场景信息

### Scene-Advanced (4)
- `list-project-scenes` - 列出所有场景
- `get-scene-structure` - 获取场景结构详情
- `list-open-scenes` - 列出当前打开的场景标签页
- `close-scene-tab` - 关闭场景标签页

### Editor (4)
- `get-editor-state` - 获取当前编辑器状态
- `run-project` - 运行项目
- `stop-project` - 停止运行中的项目
- `execute-editor-script` - 执行 GDScript 脚本

### Editor-Advanced (12)
- `get-selected-nodes` - 获取选中的节点
- `set-editor-setting` - 修改编辑器设置
- `get-editor-screenshot` - 截取编辑器视口截图
- `get-signals` - 检查节点信号和连接
- `reload-project` - 重新扫描项目文件系统
- `select-node` - 在场景中选择节点并聚焦检查器
- `select-file` - 在文件系统面板中选择文件
- `get-inspector-properties` - 检查节点/资源的属性元数据
- `list-export-presets` - 列出导出预设
- `inspect-export-templates` - 检查已安装的导出模板
- `validate-export-preset` - 验证导出预设
- `run-export` - 运行 Godot CLI 导出

### Debug (3 核心 + 68 高级)
- `get-editor-logs` - 获取编辑器/运行时日志
- `debug-print` - 打印调试信息
- `clear-output` - 清除 MCP/编辑器输出缓冲
- `get-performance-metrics` - 获取性能数据
- `get-debugger-sessions` - 列出编辑器调试会话和 active/break 状态
- `set-debugger-breakpoint` - 启用或禁用调试断点
- `send-debugger-message` - 向运行中的游戏调试器发送自定义消息
- `toggle-debugger-profiler` - 在活动会话中切换 EngineProfiler 通道
- `get-debugger-messages` - 读取 bridge 捕获的运行时自定义消息
- `add-debugger-capture-prefix` - 捕获更多 EngineDebugger 消息前缀
- `get-debug-stack-frames` - 读取已暂停会话捕获到的脚本栈帧
- `get-debug-stack-variables` - 读取指定栈帧的局部变量、成员变量和全局变量
- `install-runtime-probe` - 向当前场景添加 MCP 运行时探针节点
- `remove-runtime-probe` - 从当前场景移除 MCP 运行时探针节点
- `request-debug-break` - 请求运行时探针进入 Godot 调试暂停循环
- `send-debug-command` - 向已暂停会话发送 step/next/out/continue/stack 调试命令
- `get-runtime-info` - 通过探针查询运行时指标（FPS、节点数等）
- `await-scene-ready` - 通过探针等待指定场景加载就绪
- `get-runtime-scene-tree` - 从运行中的游戏读取实时场景树
- `inspect-runtime-node` - 检查运行时节点及其可序列化属性
- `update-runtime-node-property` - 修改运行时节点上的属性
- `call-runtime-node-method` - 调用运行时节点上的方法
- `evaluate-runtime-expression` - 在运行中的游戏计算 GDScript 表达式
- `await-runtime-condition` - 轮询运行时表达式直到为真或超时
- `assert-runtime-condition` - 断言运行时表达式在超时内变为真
- `get-debug-threads` - 返回 DAP 样式调试器线程
- `get-debug-state-events` - 读取记录的调试器状态转换
- `get-debug-output` - 读取分类的运行时调试器输出
- `get-debug-scopes` - 将栈变量分组为 DAP 风格的 scope
- `get-debug-variables` - 解析 DAP 风格的变量引用
- `expand-debug-variable` - 通过 scope 和路径展开调试变量
- `evaluate-debug-expression` - 在调试上下文评估表达式
- `debug-step-into / debug-step-over / debug-step-out / debug-continue` - 调试执行控制
- `debug-step-into-and-wait / debug-step-over-and-wait / debug-step-out-and-wait / debug-continue-and-wait` - 调试执行控制（等待状态）
- `await-debugger-state` - 检查调试器会话执行状态
- `get-runtime-performance-snapshot` - 捕获运行时性能快照
- `get-runtime-memory-trend` - 捕获运行时内存趋势
- `create-runtime-node` - 在运行中游戏创建节点
- `delete-runtime-node` - 从运行中游戏删除节点
- `simulate-runtime-input-event` - 注入结构化 InputEvent
- `simulate-runtime-input-action` - 注入 InputEventAction
- `list-runtime-input-actions` - 列出运行时 InputMap 动作
- `upsert-runtime-input-action` - 创建或更新运行时 InputMap 动作
- `remove-runtime-input-action` - 移除运行时 InputMap 动作
- `list-runtime-animations` - 列出运行时动画
- `play-runtime-animation` - 播放运行时动画
- `stop-runtime-animation` - 停止运行时动画
- `get-runtime-animation-state` - 获取运行时动画播放状态
- `get-runtime-animation-tree-state` - 获取运行时 AnimationTree 状态
- `set-runtime-animation-tree-active` - 启用/禁用 AnimationTree
- `travel-runtime-animation-tree` - 转移运行时动画状态机
- `get-runtime-material-state` - 解析运行时节点材质绑定
- `get-runtime-theme-item` - 解析运行时 Control 主题项
- `set-runtime-theme-override` - 应用运行时主题覆盖
- `clear-runtime-theme-override` - 移除运行时主题覆盖
- `get-runtime-shader-parameters` - 列出运行时着色器参数
- `set-runtime-shader-parameter` - 更新运行时着色器 uniform
- `list-runtime-tilemap-layers` - 列出运行时 TileMap 层
- `get-runtime-tilemap-cell` - 获取运行时 TileMap 单元格数据
- `set-runtime-tilemap-cell` - 写入/擦除运行时 TileMap 单元格
- `list-runtime-audio-buses` - 列出运行时音频总线
- `get-runtime-audio-bus` - 获取运行时音频总线状态
- `update-runtime-audio-bus` - 更新运行时音频总线
- `get-runtime-screenshot` - 捕获运行时视口截图

### Project (3 核心 + 23 高级)
- `get-project-info` - 获取项目信息
- `get-project-settings` - 获取项目设置
- `list-project-resources` - 列出项目资源
- `create-resource` - 创建新资源
- `get-project-structure` - 获取项目目录结构
- `list-project-tests` - 发现和列出可运行的项目测试
- `run-project-test` - 运行单个项目测试
- `run-project-tests` - 运行多个项目测试
- `list-project-input-actions` - 列出项目 InputMap 动作
- `upsert-project-input-action` - 创建或更新项目 InputMap 动作
- `remove-project-input-action` - 移除项目 InputMap 动作
- `list-project-autoloads` - 列出项目自动加载条目
- `list-project-global-classes` - 列出项目全局脚本类
- `get-class-api-metadata` - 获取 ClassDB 或全局类 API 元数据
- `inspect-csharp-project-support` - 检查 C# 项目支持文件
- `compare-render-screenshots` - 比较两张截图并报告差异
- `inspect-tileset-resource` - 检查 TileSet 资源
- `reimport-resources` - 通过导入管线重新导入资源
- `get-import-metadata` - 获取资源导入元数据
- `get-resource-uid-info` - 检查 ResourceUID 映射
- `fix-resource-uid` - 确保资源有持久化 UID
- `get-resource-dependencies` - 列出资源依赖
- `scan-missing-resource-dependencies` - 查找破损的依赖引用
- `scan-cyclic-resource-dependencies` - 查找循环依赖链
- `detect-broken-scripts` - 扫描脚本语法错误
- `audit-project-health` - 运行项目健康审计

## 🔒 安全建议

- ✅ **生产环境**：始终启用身份验证（`auth_enabled = true`）
- ✅ **令牌**：使用强令牌（≥16 个字符，包含字母、数字、特殊字符）
- ✅ **存储**：不要将令牌提交到版本控制
- ⚠️ **远程访问**：使用 HTTPS（TLS/SSL）进行网络访问

## 📋 要求

- Godot Engine 4.x（推荐 4.5 或更高版本）
- 无额外依赖（原生实现）

## 📖 文档

详细文档请查看 `docs/current/` 文件夹：
- [快速开始指南](https://github.com/yurineko73/Godot-MCP-Native/blob/main/docs/current/quickstart.md)
- [架构设计](https://github.com/yurineko73/Godot-MCP-Native/blob/main/docs/current/architecture.md)
- [工具参考](https://github.com/yurineko73/Godot-MCP-Native/blob/main/docs/current/tools-reference.md)
- [测试指南](https://github.com/yurineko73/Godot-MCP-Native/blob/main/docs/current/testing-guide.md)

## 🤝 贡献

欢迎贡献！请随时提交 Pull Request。

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](https://github.com/yurineko73/Godot-MCP-Native/blob/main/LICENSE) 文件。

## 👤 作者

**yurineko73**

## 🙏 致谢

- Godot 引擎团队带来的出色游戏引擎
- 模型上下文协议 (MCP) 规范
- Anthropic 的 Claude AI 启发了此集成

---

**注意**：这是一个社区插件，与 Godot Engine 或 Anthropic 无官方关联。
