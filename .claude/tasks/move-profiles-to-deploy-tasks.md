# Project Tasks

Move profiles from scanner/profiles to deployments/<client>, where <client> is the specific clients deploy folder. An example profile.yaml template should be available inside a deployuThe intention is to work with several profiles specific for each clients deployment context. 
```
Execute task: [task-name]
```

The agent will read this file, load the task definition, validate it against your seed document and project.yaml, then guide you through each step.

---

## Task Template

```markdown
### move profiles.yaml to deployments/client


**Inputs:**
- current directory: scanner/profiles

**Outputs:**
- target directory: deployments/<client>
- code adjust for the new location
erns from your seed document this implements]

**Acceptance Criteria:**
- profiles.yaml moved to deployments/<client>
- deployment/example/profiles.yaml created as template for future profiles
- code references updated to reflect new location
- tests updated to reflect new location
- tests executed and passing with new location

**Execution Flow:**
1. READ — agent summarizes seed document scope, project.yaml constraints, and task definition
2. PLAN — agent proposes structure, data sources, and validation approach
3. APPROVE — you review plan, request changes, or approve
4. IMPLEMENT — agent builds the output
5. VERIFY — agent validates control references and alignment with seed document
6. REPORT — agent presents output with verification results
```
---