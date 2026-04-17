# LeanSecurity — [Project Name]
## Project Seed Document v1.0
**Classification:** [LeanSecurity Internal IP | Client Delivery | Open Source]  
**Status:** [Architecture in progress | Architecture decided, build not started | Month N build in progress]  
**Last updated:** [Month Year]

---

## 1. What This Is

[One paragraph: what does this project do, in plain language. What is the end-to-end flow — what goes in, what comes out, what value does it produce?]

[One sentence: who owns this. Is it LeanSecurity IP, a client deliverable, or open source?]

[If applicable: who is the proof-of-concept client? What is their relationship to this codebase?]

### Project Separation

[Define how this project relates to other LeanSecurity projects. Which projects does it consume from? Which projects consume its outputs? What does it NOT own?]

| Project | Asset Type | Owns |
|---|---|---|
| `LeanSecurity — CSFLite` | Framework IP | [what CSFLite owns in this context] |
| `LeanSecurity — [Client]` | Client delivery | [what the client project owns] |
| `LeanSecurity — [This Project]` | [IP type] | [what this project owns — be specific] |

---

## 2. Architecture Pattern

[Name the architecture pattern. e.g. "Collector/Adapter + Canonical Event Bus", "File-Driven Intake + Per-Program Standards", "Monolithic API", "Event-Sourced Pipeline". One sentence describing the variant.]

### Layers

[Describe the distinct layers of the system. For each layer: what is its responsibility, what does it produce, what does it NOT do. Typically 2-3 layers.]

**[Layer 1 Name]**  
[Responsibility. What it does. What it produces. What it never touches.]

**[Layer 2 Name]**  
[Responsibility. What it does. What it produces. What it never touches.]

### Flow

[ASCII diagram showing the data/event flow from input to output. Label each stage. Show where persistence happens, where scoring happens, where output is generated.]

```
[Input Source]
      │
      ▼
 [Stage 1]          ← [what happens here]
      │
      ▼
 [Stage 2]          ← [what happens here]
      │
      ▼
 [Stage N]          ← [what happens here]
      │
      ▼
 [Output]           ← [what is produced]
```

### Delivery Mode

[How does data flow through the system in practice? Synchronous? Batch? Event-driven? Queue-based?]

[If applicable: what is built now vs. what is designed for but deferred?]

---

## 3. Interface Contracts

[Define the data contracts between layers, between this system and external systems, or between this system and CSFLite. These are the schemas, message formats, or file standards that form the system's boundaries.]

[For each contract, specify:]
- [What it is (schema, file format, API contract)]
- [Who produces it and who consumes it]
- [Field-level specification with types and descriptions]
- [Design rules (immutability, validation strictness, versioning)]

### [Contract 1 Name]

[Description of this contract's purpose]

| Field | Type | Description |
|---|---|---|
| `field_name` | `type` | [what this field represents] |

### [Contract 2 Name]

[Repeat as needed]

### Design Rules

- [Rule 1]
- [Rule 2]
- [Rule N]

---

## 4. Component Registry

[List the concrete components, modules, or services that will be built. For each: name, source/domain, status.]

| Component | Source/Domain | Status |
|---|---|---|
| [Name] | [what it connects to or what it does] | [Month N | Planned | Complete] |

---

## 5. Repository Structure

[Show the directory tree for each repo this project touches. Annotate key files and directories. Call out boundary rules explicitly.]

### `[repo-name]`

```
[repo-name]/
├── [directory]/
│   └── [file]          ← [what this is]
├── [directory]/
│   └── [file]          ← [what this is]
└── README.md
```

### Boundary Rules

[State which modules can import from which. These are non-negotiable architectural constraints.]

- `[module A]` never imports from `[module B]`.
- [Additional boundary rules]

---

## 6. Database Schema

[If the project has persistence, define the tables, their purpose, and multi-tenancy strategy.]

| Table | Purpose |
|---|---|
| `table_name` | [what this table stores, immutability rules, key relationships] |

[Multi-tenancy approach: how is client data isolated?]

---

## 7. Hosting Stack

[Where does this run? Who hosts it? What infrastructure does it need?]

### Infrastructure Needs

[List what the system requires abstractly — before picking vendors.]

| Need | Interface/Constraint | Notes |
|------|---------------------|-------|
| [e.g. Database] | [e.g. PostgreSQL 15+] | [any specifics] |
| [e.g. Object Store] | [e.g. S3-compatible] | [any specifics] |

### Deployment Profile — [Target Environment]

[Map abstract needs to concrete services for the first deployment target.]

| Need | Service | Notes |
|------|---------|-------|
| [e.g. Database] | [e.g. Azure Database for PostgreSQL] | [specifics] |

[Why this cloud/environment first? State the rationale.]

### Future Profiles

[If applicable: what other deployment targets are supported by the architecture but not yet built?]

---

## 8. CSFLite Interface Contract

[How does this project interact with CSFLite? What does the mapping engine read? What fields does it use?]

### `controls.yaml` — Expected Schema

```yaml
[Show the expected shape of the controls file this project consumes]
```

### What the [Scoring/Mapping Component] Uses

| Field | Used for |
|---|---|
| `field` | [how this project uses it] |

[State explicitly: the mapping engine does not hardcode control IDs, weights, or scoring rules.]

---

## 9. Proof-of-Concept — Build Status

### [Client Name] — Milestones

| Month | Milestone |
|---|---|
| 1 | [what gets built] |
| 2 | [what gets built] |
| N | [what gets built] |

### Current Status (Month N)

**Decided, not yet built:**
- [item]

**In progress:**
- [item]

### Client Config (expected structure)

```yaml
[Show the expected client configuration file]
```

---

## 10. Key Design Decisions — Locked

[These become ADRs when decomposed into the template. Each row is one decision.]

| Decision | Choice | Rationale |
|---|---|---|
| [what was decided] | [the choice made] | [why] |

---

## 11. What This Project Does Not Own

[Explicit list of what is out of scope. Prevents scope creep and clarifies boundaries with other projects.]

- [thing 1] — [where it lives instead]
- [thing 2] — [where it lives instead]
