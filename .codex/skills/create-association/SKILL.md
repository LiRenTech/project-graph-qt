---
name: create-association
description: Create a persistent relationship object between Project Graph stage entities while preserving live geometry, collision, references, serialization, and undo history.
metadata:
  short-description: Create a Project Graph Association
---

# Create Association

Use for persistent relationships between stage objects, such as a new edge type. Read the repository root `AGENTS.md` first.

- All Godot files must be read or written with `mcp__godot_mcp__` tools. Never edit `.tscn` or `.gd` with text tools, and never use computer use on Godot.
- Inspect `Association` and `LineEdge` before implementation. Extend `Association -> StageObject`; export only persistent endpoint, reference, and style data.
- Build visuals and interaction surfaces from child nodes such as `Line2D`, `Polygon2D`, and `CollisionShape2D`. Never use `_draw()` or low-level canvas APIs.
- Recompute geometry from referenced entities in the appropriate update callback so moving endpoints keeps the association attached. Derive collision geometry from the collision child.
- Store references as stable object IDs and rely on registry two-pass restoration. Do not serialize transient points that can be derived from endpoint state.
- Register the association scene and type name in `StageObjectRegistry.SCENES` through Godot MCP. Invalid or deleted references must hide or fail harmlessly.
- Consider creation/edit operations as one `History` transaction and keep scene composition inspectable. Avoid unrelated refactors.

When handing off, list changed scripts/scenes, MCP tool categories used, and a manual check: create the relationship, move both endpoints, save/load it, undo/redo it, delete an endpoint, and inspect registry registration, references, collision, and update behavior if it fails. Do not claim verification was run unless explicitly authorized.
