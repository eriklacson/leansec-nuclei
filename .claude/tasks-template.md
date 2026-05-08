# Project Tasks

Define your project's tasks here. Each task enforces the READ → PLAN → APPROVE → IMPLEMENT → VERIFY → REPORT loop and validates alignment with your seed document (if present).

Copy this template for each task and fill in the fields. When executing a task in Claude Code, reference it by name:

```
Execute task: [task-name]
```

The agent will read this file, load the task definition, validate it against your seed document and project.yaml, then guide you through each step.

---

## Task Template

```markdown
### [Task Name]

**Type:** doc | app
**Subtype:** [gap-analysis | policy | mapping | assessment-report | executive-summary | cli | api | web]
**Description:** [One sentence: what this task produces and who it's for]

**Inputs:**
- [What the agent needs from you before starting]
- [Data, decisions, or approvals required]

**Outputs:**
- [What the agent will produce]
- [Where it will be written (docs/, src/, etc.)]

**Seed Document Alignment:**
Controls addressed: [list of control IDs from your seed document, or "all"]
Sections referenced: [which sections of seed-document.md this task uses, e.g., "section 3: Interface Contracts, section 8: CSFLite Interface"]
Architecture patterns: [which patterns from your seed document this implements]

**Acceptance Criteria:**
- [Verifiable criteria from project.yaml or task-specific criteria]
- [How the agent will validate the output]

**Execution Flow:**
1. READ — agent summarizes seed document scope, project.yaml constraints, and task definition
2. PLAN — agent proposes structure, data sources, and validation approach
3. APPROVE — you review plan, request changes, or approve
4. IMPLEMENT — agent builds the output
5. VERIFY — agent validates control references and alignment with seed document
6. REPORT — agent presents output with verification results
```
---

## Your Tasks

### Normalize Nuclei JSONL into standardized JSON files

**Type:** app
**Subtype:** cli 
**Description:** Consolidated findings from JSON in `result/` into a standard json file with fields for SLO tracking app component.

**Inputs:**
- Nuclei JSONL output from `results/<client>/YYYY-MM-DD/`

**Outputs:**
- `results/result-YYYY-MM-DD.json` — Consolidated json file with standardized fields for SLO tracking app component

**Context**
- refer to code in scanner/nuclei_convert_jsonl.py for current implementation, which is a one-off script. This task is to formalize it into a reusable CLI tool that can be run on demand or scheduled.
- helper functions in nuclei_json_converter.py can be reused for parsing and field mapping logic.
- consolidate in scan.ph for single command scan and transform.

**Seed Document Alignment:**
Sections referenced: Normalized JSON Output — Normalized Scan Results

**Acceptance Criteria:**
- `results/result-YYYY-MM-DD.json` with fields properly mapped and consolidated definition in Seed Document

**Execution Flow:**
1. READ — agent tasks.md and validate alignment with project.yaml and seed document
2. PLAN — agent proposes code change
3. APPROVE — you confirm scope and detail level
4. IMPLEMENT — agent generates modifies code
5. VERIFY — agent validates field mapping and output structure against seed document
6. REPORT — agent presents report with verification results
