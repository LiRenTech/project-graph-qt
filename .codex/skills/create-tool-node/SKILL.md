---
name: create-tool-node
description: Create a transient stage interaction tool for Project Graph using real scene nodes for gestures, previews, highlights, and collision feedback.
metadata:
  short-description: Create a Project Graph tool node
---

# Create Tool Node

Use for transient stage tools such as connection creators, slicing gestures, selection overlays, and previews. Read the repository root `AGENTS.md` first.

- All Godot files must be read or written with `mcp__godot_mcp__` tools. Never edit `.tscn` or `.gd` with text tools, and never use computer use on Godot.
- Put the script under `res://src/` (or a focused `src` subdirectory), usually extending `Node2D`. Do not extend `StageObject` unless the tool itself is persistent project content.
- Add the tool node to the relevant stage scene through Godot MCP. Expose `target_root` and tunable appearance as exported properties when scene configuration needs them.
- Represent every visible preview or highlight with child nodes such as `Line2D`, `Polygon2D`, `ColorRect`, or `Label`; update their properties and visibility. Never use `_draw()`, `RenderingServer`, or other low-level canvas APIs.
- Calculate geometry in world coordinates and use `to_local()` only when assigning points to a tool's local drawing node. Derive hit geometry from target `CollisionShape2D` children.
- Choose input propagation deliberately: `_input` for global gestures, `_unhandled_input` for stage gestures, and control callbacks for UI editing. Mark events handled only after claiming them.
- If the tool mutates persistent objects, wrap the complete gesture in `History.begin_transaction()` / `commit()`. Hide or remove all temporary feedback on success, cancel, and invalid-target paths.

When handing off, list changed scripts/scenes, MCP tool categories used, and a manual check: trigger the gesture, inspect preview/highlight behavior, complete and cancel it, test undo/redo for mutations, and inspect scene-tree attachment, coordinate conversion, input ownership, and cleanup if it fails. Do not claim verification was run unless explicitly authorized.
