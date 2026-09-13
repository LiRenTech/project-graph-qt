# Godot MCP Native (Model Context Protocol)

[中文版本](https://github.com/yurineko73/Godot-MCP-Native/blob/main/README.zh.md)

![Godot Version](https://img.shields.io/badge/Godot-4.x-blue?logo=godot-engine)
![License](https://img.shields.io/badge/License-MIT-green)
![Version](https://img.shields.io/badge/Version-1.0.8-brightgreen)

A powerful Godot Engine plugin that integrates AI assistants (Claude, etc.) via the Model Context Protocol (MCP). Enable AI to directly read and modify your Godot projects - scenes, scripts, nodes, and resources - all through natural language.

## 🚀 Features

- **Full Project Access**: AI assistants can read and modify scripts, scenes, nodes, and resources
- **Native Implementation**: No Node.js dependency required - runs entirely within Godot
- **Real-time Editing**: Apply AI suggestions directly in the editor
- **Comprehensive Tool Set** (155 tools — 30 core + 125 supplementary):
  - **Node Tools** (9 core + 11 advanced): Create, modify, manage scene nodes, duplicate, move, rename, signal connections, anchor presets, group management, batch operations, scene auditing
  - **Script Tools** (7 core + 8 advanced): Edit, analyze, create, attach, validate GDScript and C# files, execute scripts, search in files, symbol indexing, definition & reference lookup
  - **Scene Tools** (4 core + 4 advanced): Manipulate scene structure, save scenes, list/open/close scene tabs, project scene listing
  - **Editor Tools** (4 core + 12 advanced): Control editor functionality, screenshot, signal inspection, filesystem reload, node/file selection, export management, property inspector
  - **Debug Tools** (3 core + 68 advanced): Logging, debugger sessions, breakpoints, stack/variable inspection, profilers, runtime probe, animation/audio/shader/tilemap runtime control, debug execution control, await_scene_ready
  - **Project Tools** (3 core + 23 advanced): Access project settings, list resources, create resources, run tests, manage input mappings, inspect autoloads/global classes, resource diagnostics & health audit

## 🖥️ gdmcp CLI

This plugin includes a companion **gdmcp CLI** for coding agents (Codex, Claude Code, etc.)
that reduces model context usage by ~30,000 tokens compared to MCP. Install it from the
**CLI Tools** tab in the MCP dock panel, or download from
[GitHub Releases](https://github.com/yurineko73/Godot-MCP-Native/releases).

See [CLI README](https://github.com/yurineko73/Godot-MCP-Native/blob/main/cli/gdmcp/README.md) for details.

## 📦 Installation

### Method 1: Asset Library (Recommended)
1. Open your Godot project
2. Go to **AssetLib** tab in the editor
3. Search for "Godot MCP Native"
4. Click **Download** and then **Install**

### Method 2: Manual Installation
1. Download or clone this repository
2. Copy the `addons/godot_mcp` folder to your project's `addons/` directory
3. Open your project in Godot
4. Go to **Project > Project Settings > Plugins**
5. Enable "Godot MCP Native" plugin

## 🔧 Usage

### Enabling the Plugin
1. Open **Project > Project Settings > Plugins**
2. Locate "Godot MCP Native" in the list
3. Set the status to **Enable**

### Configuring MCP Server
The plugin provides two transport modes:

#### HTTP Mode (for remote access)
- Best for: Network-based AI integration
- Configuration: Set `transport_mode = "http"` and configure `http_port` (default: 9080)
- Optional: Enable `auth_enabled` and set `auth_token` for security

### Connecting with Claude Desktop

First, install the `mcp-remote` package:
```bash
npm install mcp-remote
```

#### HTTP Mode Configuration
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

### Connecting with Cursor / Trae

#### HTTP Mode Configuration
```json
{
  "mcpServers": {
    "godot-mcp": {
      "url": "http://localhost:9080/mcp"
    }
  }
}
```

With authentication:
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

### Connecting with Cline

#### HTTP Mode Configuration

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

### Connecting with OpenCode

#### HTTP Mode Configuration

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

### Connecting with Codex

#### HTTP Mode Configuration

```toml
[mcp_servers]

[mcp_servers.godot-mcp]
type = "streamableHttp"
url = "http://localhost:9080/mcp"
```

## 💬 Example Prompts

Once connected, you can interact with your Godot project through Claude:

```
@mcp godot-mcp read godot://script/current

I need help optimizing my player movement code. Can you suggest improvements?
```

```
@mcp godot-mcp get-scene-tree

Add a cube in the middle of the scene and create a camera that looks at it.
```

```
Create a main menu with Play, Options, and Quit buttons
```

```
Implement a day/night cycle system with dynamic lighting
```

## 📚 Available Commands

### Node-Write (6)
- `create-node` - Create a new node
- `delete-node` - Delete a node
- `update-node-property` - Update node properties
- `duplicate-node` - Duplicate a node and its children
- `move-node` - Move a node to a new parent
- `rename-node` - Rename a node in the scene

### Node-Read (3)
- `get-scene-tree` - Get scene tree structure
- `get-node-properties` - Get properties of a specific node
- `list-nodes` - List nodes under a parent

### Node-Write-Advanced (5)
- `set-anchor-preset` - Set anchor preset for Control nodes
- `connect-signal` - Connect a signal between nodes
- `disconnect-signal` - Disconnect a signal connection
- `set-node-groups` - Set group memberships for a node
- `add-resource` - Add a resource child node (collision shape, mesh, etc.)

### Node-Advanced (6)
- `get-node-groups` - Get groups a node belongs to
- `find-nodes-in-group` - Find all nodes in a specific group
- `batch-update-node-properties` - Batch update multiple node properties in one UndoRedo action
- `batch-scene-node-edits` - Apply batch scene node create/delete/move edits in one UndoRedo action
- `audit-scene-node-persistence` - Audit node owner and persistence state for the scene
- `audit-scene-inheritance` - Audit inherited/instanced scene structure

### Script (7)
- `list-project-scripts` - List all scripts
- `read-script` - Read a specific script
- `modify-script` - Update script content
- `create-script` - Create a new script
- `get-current-script` - Get currently editing script
- `attach-script` - Attach an existing script to a node
- `execute-script` - Execute GDScript expression

### Script-Advanced (8)
- `analyze-script` - Analyze script structure
- `validate-script` - Validate GDScript syntax
- `search-in-files` - Search project files
- `list-project-script-symbols` - Index script symbols across GDScript and C# files
- `find-script-symbol-definition` - Find definition locations for a script symbol
- `find-script-symbol-references` - Find textual references to a script symbol
- `rename-script-symbol` - Rename a script symbol across project files
- `open-script-at-line` - Open a script at a specific line in the editor

### Scene (4)
- `create-scene` - Create a new scene
- `save-scene` - Save current scene
- `open-scene` - Open a scene
- `get-current-scene` - Get current scene info

### Scene-Advanced (4)
- `list-project-scenes` - List all scenes
- `get-scene-structure` - Get scene structure details
- `list-open-scenes` - List currently open scene tabs
- `close-scene-tab` - Close a scene tab

### Editor (4)
- `get-editor-state` - Get current editor state
- `run-project` - Run the project
- `stop-project` - Stop the running project
- `execute-editor-script` - Execute GDScript script

### Editor-Advanced (12)
- `get-selected-nodes` - Get selected nodes
- `set-editor-setting` - Modify editor settings
- `get-editor-screenshot` - Capture an editor viewport screenshot
- `get-signals` - Inspect node signals and connections
- `reload-project` - Rescan the project filesystem
- `select-node` - Select a node in the scene and focus in Inspector
- `select-file` - Select a file in the FileSystem dock
- `get-inspector-properties` - Inspect node/resource properties like the Inspector
- `list-export-presets` - List export presets
- `inspect-export-templates` - Inspect installed export templates
- `validate-export-preset` - Validate an export preset
- `run-export` - Run a Godot CLI export

### Debug (3 core + 68 advanced)
- `get-editor-logs` - Get editor/runtime logs
- `debug-print` - Print debug info
- `clear-output` - Clear MCP/editor output buffers
- `get-performance-metrics` - Get performance data
- `get-debugger-sessions` - List editor debugger sessions and active/break state
- `set-debugger-breakpoint` - Enable or disable debugger breakpoints
- `send-debugger-message` - Send custom messages to the running game debugger
- `toggle-debugger-profiler` - Toggle EngineProfiler channels in active sessions
- `get-debugger-messages` - Read custom runtime messages captured by the bridge
- `add-debugger-capture-prefix` - Capture additional EngineDebugger message prefixes
- `get-debug-stack-frames` - Read captured script stack frames from a breaked session
- `get-debug-stack-variables` - Read locals, members, and globals for a captured stack frame
- `install-runtime-probe` - Add the MCP runtime probe node to the current scene
- `remove-runtime-probe` - Remove the MCP runtime probe node from the current scene
- `request-debug-break` - Ask the runtime probe to enter Godot's debug break loop
- `send-debug-command` - Send step/next/out/continue/stack debugger commands to breaked sessions
- `get-runtime-info` - Query runtime metrics (FPS, node count, etc.) through the probe
- `await-scene-ready` - Wait until a specific scene is loaded through the probe
- `get-runtime-scene-tree` - Read the live runtime scene tree from the running game
- `inspect-runtime-node` - Inspect a live runtime node and its serializable properties
- `update-runtime-node-property` - Modify a property on a live runtime node
- `call-runtime-node-method` - Call a method on a live runtime node
- `evaluate-runtime-expression` - Evaluate a GDScript expression in the running game
- `await-runtime-condition` - Poll a runtime expression until truthy or timeout
- `assert-runtime-condition` - Assert a runtime expression becomes truthy within timeout
- `get-debug-threads` - Return DAP-style debugger threads
- `get-debug-state-events` - Read recorded debugger state transitions
- `get-debug-output` - Read categorized runtime debugger output
- `get-debug-scopes` - Group stack variables into DAP-like scopes
- `get-debug-variables` - Resolve DAP-style variable references
- `expand-debug-variable` - Expand a debug variable by scope and path
- `evaluate-debug-expression` - Evaluate an expression in debugger context
- `debug-step-into` / `debug-step-over` / `debug-step-out` / `debug-continue` - Debug execution control
- `debug-step-into-and-wait` / `debug-step-over-and-wait` / `debug-step-out-and-wait` / `debug-continue-and-wait` - Debug execution with state wait
- `await-debugger-state` - Check debugger session execution state
- `get-runtime-performance-snapshot` - Capture runtime performance snapshot
- `get-runtime-memory-trend` - Capture runtime memory trend
- `create-runtime-node` - Create a node in the running game
- `delete-runtime-node` - Delete a node from the running game
- `simulate-runtime-input-event` - Inject structured InputEvent
- `simulate-runtime-input-action` - Inject InputEventAction
- `list-runtime-input-actions` - List runtime InputMap actions
- `upsert-runtime-input-action` - Create/update a runtime InputMap action
- `remove-runtime-input-action` - Remove a runtime InputMap action
- `list-runtime-animations` - List animations on a runtime AnimationPlayer
- `play-runtime-animation` - Play a runtime animation
- `stop-runtime-animation` - Stop a runtime animation
- `get-runtime-animation-state` - Get runtime animation playback state
- `get-runtime-animation-tree-state` - Get runtime AnimationTree state
- `set-runtime-animation-tree-active` - Enable/disable runtime AnimationTree
- `travel-runtime-animation-tree` - Travel runtime animation state machine
- `get-runtime-material-state` - Resolve runtime node material binding
- `get-runtime-theme-item` - Resolve runtime Control theme item
- `set-runtime-theme-override` - Apply runtime theme override
- `clear-runtime-theme-override` - Remove runtime theme override
- `get-runtime-shader-parameters` - List runtime shader parameters
- `set-runtime-shader-parameter` - Update runtime shader uniform
- `list-runtime-tilemap-layers` - List runtime TileMap layers
- `get-runtime-tilemap-cell` - Get runtime TileMap cell data
- `set-runtime-tilemap-cell` - Write/erase runtime TileMap cell
- `list-runtime-audio-buses` - List runtime audio buses
- `get-runtime-audio-bus` - Get runtime audio bus state
- `update-runtime-audio-bus` - Update runtime audio bus
- `get-runtime-screenshot` - Capture runtime viewport screenshot

### Project (3 core + 23 advanced)
- `get-project-info` - Get project information
- `get-project-settings` - Get project settings
- `list-project-resources` - List project resources
- `create-resource` - Create a new resource
- `get-project-structure` - Get project directory structure
- `list-project-tests` - Discover and list runnable project tests
- `run-project-test` - Run a single project test
- `run-project-tests` - Run multiple project tests
- `list-project-input-actions` - List project InputMap actions
- `upsert-project-input-action` - Create or update a project InputMap action
- `remove-project-input-action` - Remove a project InputMap action
- `list-project-autoloads` - List project autoload entries
- `list-project-global-classes` - List project global script classes
- `get-class-api-metadata` - Get ClassDB or global class API metadata
- `inspect-csharp-project-support` - Inspect C# project support files
- `compare-render-screenshots` - Compare two screenshots for pixel differences
- `inspect-tileset-resource` - Inspect a TileSet resource
- `reimport-resources` - Reimport resources through the import pipeline
- `get-import-metadata` - Get resource import metadata
- `get-resource-uid-info` - Inspect ResourceUID mappings
- `fix-resource-uid` - Ensure a resource has a persisted UID
- `get-resource-dependencies` - List resource dependencies
- `scan-missing-resource-dependencies` - Find broken dependency references
- `scan-cyclic-resource-dependencies` - Find cyclic dependency chains
- `detect-broken-scripts` - Scan scripts for syntax errors
- `audit-project-health` - Run a project health audit

## 🔒 Security Recommendations

- ✅ **Production**: Always enable authentication (`auth_enabled = true`)
- ✅ **Token**: Use a strong token (≥16 characters with letters, numbers, special characters)
- ✅ **Storage**: Don't commit tokens to version control
- ⚠️ **Remote Access**: Use HTTPS (TLS/SSL) for network access

## 📋 Requirements

- Godot Engine 4.x (recommended 4.5 or higher)
- No additional dependencies (native implementation)

## 📖 Documentation

For detailed documentation, see the `docs/current/` folder:
- [Quick Start Guide](https://github.com/yurineko73/Godot-MCP-Native/blob/main/docs/current/quickstart.md)
- [Architecture Design](https://github.com/yurineko73/Godot-MCP-Native/blob/main/docs/current/architecture.md)
- [Tools Reference](https://github.com/yurineko73/Godot-MCP-Native/blob/main/docs/current/tools-reference.md)
- [Testing Guide](https://github.com/yurineko73/Godot-MCP-Native/blob/main/docs/current/testing-guide.md)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/yurineko73/Godot-MCP-Native/blob/main/LICENSE) file for details.

## 👤 Author

**yurineko73**

## 🙏 Acknowledgments

- Godot Engine team for the amazing game engine
- Model Context Protocol (MCP) specification
- Claude AI by Anthropic for inspiring this integration

---

**Note**: This is a community plugin and is not officially affiliated with Godot Engine or Anthropic.
