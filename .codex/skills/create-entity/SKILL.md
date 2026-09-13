---
name: create-entity
description: Create a new persistent, movable Entity in the Project Graph Godot editor using its scene, collision, physics, serialization, and history conventions.
metadata:
  short-description: Create a Project Graph Entity
---

# Create Entity

Use for new persistent stage objects users can move or edit directly. Read the repository root `AGENTS.md` first.

- All Godot files must be read or written with `mcp__godot_mcp__` tools. Never edit `.tscn` or `.gd` with text tools, and never use computer use on Godot.
- Inspect `StageObject`, `Entity`, and the closest existing entity, normally `TextNode`, before designing the new type.
- Put the script under `res://src/stage_object/entity/<feature>/`, extend `Entity`, keep persistent data in exported properties, and keep transient state private.
- Create the scene through Godot MCP. Use child nodes for visuals and collision; never use `_draw()` or low-level canvas APIs. The collision child is required because `StageObject.aabb` and stage tools derive geometry from it.
- Start and finish direct manipulation with `History.begin_transaction()` / `commit()`, normally moving through `RigidBody2D.linear_velocity`.
- Register the scene and type name in `StageObjectRegistry.SCENES` through Godot MCP. Ensure exported properties, `Vector2` values, and object references round-trip; references use stable object IDs, not node paths.
- Keep scene composition, node names, unique-node references, and signals inspectable. Avoid unrelated refactors.

When handing off, list changed scripts/scenes, MCP tool categories used, and a manual check: trigger creation, move/edit the entity, save/load it, undo/redo it, and inspect scene-tree attachment, collision shape, registry entry, and input handling if it fails. Do not claim verification was run unless explicitly authorized.
