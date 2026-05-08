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

### Create Scan Result Uploader to GCS

**Type:** app
**Subtype:** CLI 
**Description:** App for uploading to GCS

**Inputs:**
- scan outputs in results/<client>/<YYYY-MM-DD>

**Outputs:**
- scan outputs in gs://<client>-security-scans/nuclei/<YYYY-MM-DD> 

**Context**
Automate this process

```
# One-time: authenticate
gcloud auth login
gcloud config set project <client>-gcp-project-id

# Upload current month
MONTH=$(date +%Y-%m)
gcloud storage cp results/<client>/${MONTH}/*.jsonl gs://<client>-security-scans/nuclei/${MONTH}/

```
- client is a required command line parameter
- settings for GCP project and GCS path should be in .env
- app assumes user has authenticated to GCP or flag and exit otherwise
- this is for local CLI version only
 
**Seed Document Alignment:**
Not referenced

**Acceptance Criteria:**
- scan outputs in gs://<client>-security-scans/nuclei/<YYYY-MM-DD>

**Execution Flow:**
1. READ — agent tasks.md and validate alignment with project.yaml and seed document
2. PLAN — agent proposes code change
3. APPROVE — you confirm scope and detail level
4. IMPLEMENT — agent generates modifies code
5. VERIFY — agent validates field mapping and output structure against seed document
6. REPORT — agent presents report with verification results
