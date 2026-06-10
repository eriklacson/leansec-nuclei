# project.yaml — gcp-deploy Claude Code skill
#
# This file specifies the work to be executed by Claude Code to deliver the
# gcp-deploy skill: a Claude Code skill that orchestrates GCP deployment of
# the leansecurity-nuclei pipeline. The skill is shipped in the public
# repository at .claude/skills/gcp-deploy/ and is invoked by a technical
# operator (architect or client-side engineer) running Claude Code from
# their private deployment folder.
#
# Predecessor feature: gcp-cloud-deploy (the GCP Cloud Automated activation).
# That feature MUST be complete and merged before this one begins. This
# skill orchestrates the artifacts produced by that feature.

feature: gcp-deploy-skill
mode: build
version: 1
last_updated: 2026-05-22

# ──────────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────────

summary: |
  Deliver a Claude Code skill that orchestrates GCP deployment of the
  leansecurity-nuclei pipeline. The skill reads a higher-level YAML config
  (deployment.yaml) from an operator's private deployment folder, compiles
  it into Terraform tfvars, runs the bootstrap script, executes
  terraform init/plan, presents a digestible plan summary in chat, asks
  the operator to confirm, and runs terraform apply. The skill is invoked
  by intent ("deploy this to GCP") or by the /gcp-deploy slash command.

  The skill is shipped inside the public repo and uses the version of the
  Terraform module that ships with the same repo checkout. There is no
  module version pinning in the YAML. The scanner image has a known-good
  default baked into the skill, overridable per deployment for advanced
  operators.

  This skill is a runbook for Claude Code, not a CLI program. Its primary
  deliverable is SKILL.md, supplemented by schema, templates, and an
  example. Skill behavior comes from Claude Code interpreting the
  instructions, not from compiled code.

# ──────────────────────────────────────────────────────────────────────────────
# Decisions to confirm before execution
#
# These are Claude's recommended defaults locked in conversation with the
# architect. All implementations below assume these decisions hold.
# ──────────────────────────────────────────────────────────────────────────────

decisions_to_confirm:

  - id: skill_location
    decision: .claude/skills/gcp-deploy/
    rationale: |
      Lives in the public repo alongside the code it operates. Versioned
      together with the Terraform module — when the module changes shape,
      the skill changes with it in the same commit. Discoverable by
      anyone who clones the repo.

  - id: slash_command_location
    decision: .claude/commands/gcp-deploy.md
    rationale: |
      Standard Claude Code slash command convention. Thin wrapper that
      invokes the gcp-deploy skill with the current working directory.
      Provides a deterministic invocation path alongside intent-triggered
      use. If this location turns out to be wrong for the Claude Code
      version in use, Claude Code should adjust during implementation and
      flag the change.

  - id: yaml_schema_top_level_groupings
    decision: deployment, scanner, features, schedule, targets
    rationale: |
      Five top-level groupings, each cohesive. `deployment` captures
      identity (client name, GCP project, region). `scanner` pins the
      container image. `features` carries the three module flags.
      `schedule` carries cron and timezone. `targets` carries the targets
      file reference (defaults to ./targets.txt if omitted).

  - id: module_version_pinning
    decision: Skill uses the module version that ships with its repo checkout
    rationale: |
      No `module:` block in the YAML. The skill resolves the module path
      relative to its own installation (../../infra/gcp from the skill's
      location). Operators upgrade the module by upgrading their public
      repo checkout. Simplest, lowest-drift model.

  - id: scanner_image_default
    decision: Known-good default baked into the skill, overridable in YAML
    rationale: |
      The scanner image changes more often than the module (CVE template
      releases). Operators can omit the `scanner` block to get the
      skill's shipped default; advanced operators can pin to a specific
      tag for reproducibility. Default is set at the skill's release
      time to the latest semver tag of ghcr.io/leansecurity/nuclei-scanner.

  - id: targets_file_convention
    decision: |
      `targets` block stays in the YAML with `targets.file` field
      (defaults to `./targets.txt`). Architects can override the path
      for testing or special deployments.
    rationale: |
      Default behavior matches local-mode convention (poetry run python
      scanner/scan.py reads from targets.txt in the deployment folder).
      Override path exists for flexibility without forcing operators to
      think about it.

  - id: deployment_folder_location
    decision: |
      Operator's deployment folder lives at deployments/<client>/ inside
      the public repo checkout, but is gitignored. The .gitignore pattern
      excludes everything under deployments/ except deployments/_example/.
    rationale: |
      Operator works inside the repo (so the skill can resolve module
      paths relatively), but no client-identifying files are ever
      committed. .gitignore enforces this structurally rather than by
      discipline.
  - id: invocation_pattern
    decision: |
      Both intent-triggered and slash command. Operator says "deploy
      this to GCP" or invokes /gcp-deploy. Both paths reach the same
      skill behavior.
    rationale: |
      Intent-triggered works for natural use; slash command works for
      documentation and deterministic invocation. Zero cost to provide
      both.

  - id: first_invocation_behavior
    decision: |
      The skill detects whether deployment.yaml exists in the current
      folder. If yes, proceed with deployment. If no, offer to scaffold
      the folder from deployments/_example/ and prompt the operator to
      populate the YAML before continuing.
    rationale: |
      Same skill serves both fresh-setup and subsequent-deploy paths.
      Operator does not need to remember which mode they're in.
# ──────────────────────────────────────────────────────────────────────────────
# Feature-wide constraints
# ──────────────────────────────────────────────────────────────────────────────

constraints:

  - id: lightweight_skill_not_cli
    rule: |
      The skill is a runbook for Claude Code, not a polished CLI program.
      Primary deliverable is SKILL.md (natural-language instructions).
      Supporting files are templates and schemas, not executables. The
      skill may invoke real programs (gcloud, terraform, the existing
      scripts/bootstrap-gcp-client.sh) but does not reimplement them.

  - id: no_client_artifacts_in_skill
    rule: |
      Files under .claude/skills/gcp-deploy/ may not contain any
      client-identifying data. All examples use placeholder values
      (<your-client>, <your-gcp-project>, example.com, etc.). The
      annotated example YAML (deployment.example.yaml) uses generic
      illustrative values only.

  - id: depends_on_predecessor_feature
    rule: |
      The gcp-cloud-deploy feature (its project.yaml is the predecessor
      to this one) must be complete and merged before any work on this
      skill begins. Specifically, the following artifacts must exist
      and pass their own acceptance criteria:
        - infra/gcp/ Terraform module with the three flags
        - scripts/bootstrap-gcp-client.sh
        - deployments/_example/ refreshed for the GHCR model
        - docs/setup-guide.md
        - publish-image.yaml producing GHCR images
      The skill orchestrates these artifacts. It does not duplicate or
      replace any of them.
  - id: idempotent_re_runs
    rule: |
      Re-running the skill against the same deployment.yaml must be
      safe and produce the same end state. Every operation re-renders
      from the YAML rather than appending. Generated files (tfvars,
      backend.tf, main.tf) are overwritten on every run with header
      comments stating they are regenerated.

  - id: operator_in_the_loop_for_apply
    rule: |
      The skill never runs `terraform apply` without explicit operator
      confirmation in chat. Plan output is summarized; raw plan is
      available on request; apply proceeds only after the operator
      confirms with an unambiguous affirmative response.

  - id: yaml_validation_before_gcp_calls
    rule: |
      The skill validates the YAML against its schema before making any
      gcloud or terraform call. Invalid YAML fails fast with a helpful
      error pointing at the offending field. No partial progress is
      made on invalid input.

  - id: gitignore_enforcement
    rule: |
      The .gitignore policy excludes deployments/* except
      deployments/_example/. This is the structural protection against
      client artifacts leaking into the public repo. The skill never
      writes to deployments/_example/ during normal operation.
# ──────────────────────────────────────────────────────────────────────────────
# Workstreams
# ──────────────────────────────────────────────────────────────────────────────

workstreams:

  # ════════════════════════════════════════════════════════════════════════
  # B. Build — skill bundle
  # ════════════════════════════════════════════════════════════════════════

  - id: build
    title: Skill bundle
    depends_on: []
    description: |
      All files that make up the gcp-deploy skill: the SKILL.md runbook,
      the YAML schema, the annotated example, the tfvars template, and
      the slash command wrapper. Also includes the .gitignore update to
      enforce deployment folder exclusion.

    deliverables:

      - id: B1
        title: Write .claude/skills/gcp-deploy/SKILL.md
        scope: |
          The skill's main file. Natural-language instructions for Claude
          Code covering the full deployment workflow: detect folder state,
          scaffold if needed, validate YAML, render tfvars, run bootstrap,
          run terraform init/plan, summarize plan, confirm with operator,
          run apply, report results.
        files:
          - .claude/skills/gcp-deploy/SKILL.md
        required_sections:
          - "Frontmatter: name, description (intent-trigger signal), version"
          - "When to use this skill (trigger phrases and contexts)"
          - "Prerequisites Claude Code should verify before starting (gcloud installed and authenticated, terraform installed, current directory contains or could contain a deployment folder)"
          - "Workflow step 1: Detect deployment folder state"
          - "Workflow step 2: Scaffold from _example/ if needed"
          - "Workflow step 3: Validate deployment.yaml against schema"
          - "Workflow step 4: Run scripts/bootstrap-gcp-client.sh if not already done"
          - "Workflow step 5: Render tfvars, backend.tf, main.tf from the YAML"
          - "Workflow step 6: Run terraform init"
          - "Workflow step 7: Run terraform plan, capture output"
          - "Workflow step 8: Summarize plan in chat (resources created, modified, destroyed; flag any IAM bindings or destructive changes prominently)"
          - "Workflow step 9: Ask operator to confirm before apply"
          - "Workflow step 10: Run terraform apply (only after explicit confirmation)"
          - "Workflow step 11: Report results, document what was deployed, list next steps"
          - "Error handling: what to do when each step fails"
          - "Idempotency: how re-runs behave"
          - "Out of scope: what this skill does not do (first scan trigger, JSONL verification, image rebuild)"
        content_requirements:
          - "Frontmatter description is specific enough to trigger on phrases like 'deploy this to GCP', 'run the GCP deployment', 'apply the gcp-deploy skill', but not so generic that it fires on unrelated requests"
          - "Workflow steps are numbered and clearly bounded"
          - "Every step has a 'success looks like' and 'failure looks like' clause"
          - "The skill resolves the Terraform module path relative to its own location: ../../infra/gcp from .claude/skills/gcp-deploy/SKILL.md"
          - "The default scanner image tag is set as a single named constant in the SKILL.md, easy to find and update at skill release time"
          - "The skill instructions explicitly state the operator-in-the-loop rule for apply: never proceed without explicit affirmative confirmation"
          - "Plan summary section in step 8 instructs Claude Code to call out IAM bindings, public bucket policies, and destructive changes (deletions, replacements) as separate prominent items, not buried in resource counts"
        acceptance:
          - "File exists at .claude/skills/gcp-deploy/SKILL.md"
          - "Frontmatter is valid YAML and includes name, description, version"
          - "Every required section is present"
          - "Workflow has 11 numbered steps as listed above"
          - "Error handling clauses exist for: yaml validation failure, gcloud auth missing, terraform not installed, bootstrap script failure, terraform init failure, terraform plan failure, terraform apply failure"
          - "Markdown lint passes (e.g., markdownlint default config)"
      - id: B2
        title: Write .claude/skills/gcp-deploy/schema/deployment.schema.json
        scope: |
          JSON Schema for validating deployment.yaml. The schema is the
          machine-readable contract between operator and skill. Used by
          the skill in workflow step 3 to fail fast on invalid input.
        files:
          - .claude/skills/gcp-deploy/schema/deployment.schema.json
        schema_shape:
          schema_version:
            type: integer
            enum: [1]
            required: true
          deployment:
            client_name:
              type: string
              pattern: "^[a-z][a-z0-9-]{1,30}$"
              required: true
            gcp_project_id:
              type: string
              pattern: "^[a-z][a-z0-9-]{5,29}$"
              required: true
            region:
              type: string
              default: asia-southeast1
          scanner:
            image:
              type: string
              description: "Full container image URI with tag. Omit to use skill default."
              required: false
          features:
            enable_scheduler:
              type: boolean
              default: true
            enable_wif:
              type: boolean
              default: false
            enable_ar_mirror:
              type: boolean
              default: false
          schedule:
            cron:
              type: string
              default: "0 2 1-7 * 0"
              description: "First Sunday of month, 02:00. Standard cron format."
            timezone:
              type: string
              default: Etc/UTC
              description: "IANA timezone name."
          targets:
            file:
              type: string
              default: ./targets.txt
              description: "Path to targets file, relative to deployment.yaml."
        constraints:
          - "Schema uses JSON Schema draft-07 or later"
          - "additionalProperties: false on every object, to catch typos in field names"
          - "Pattern constraints match GCP and Nuclei conventions (lowercase, hyphens, length bounds)"
        acceptance:
          - "File exists and is valid JSON"
          - "Schema validates correctly using a standard validator (e.g., python jsonschema)"
          - "A minimal valid YAML (only required fields) validates successfully against the schema"
          - "A YAML with all fields populated validates successfully"
          - "A YAML with a misspelled field name fails validation with a clear error pointing at the field"
          - "A YAML with an invalid client_name (e.g., starts with digit, contains uppercase) fails validation"
      - id: B3
        title: Write .claude/skills/gcp-deploy/templates/deployment.example.yaml
        scope: |
          Annotated example deployment.yaml that operators copy as the
          starting point for their own deployments. Every field is shown
          with a comment explaining its purpose, valid values, and
          whether it is required or optional.
        files:
          - .claude/skills/gcp-deploy/templates/deployment.example.yaml
        content_requirements:
          - "Top-of-file comment block explaining what this file is and how to use it"
          - "Every field from the schema is represented, even optionals"
          - "Inline comments on every field explaining purpose and valid values"
          - "Placeholder values throughout: <your-client>, <your-gcp-project>, example.com"
          - "Comments distinguish required from optional fields"
          - "Comments indicate which fields have default values and what those defaults are"
        acceptance:
          - "File exists"
          - "File validates successfully against deployment.schema.json (with placeholders replaced by valid values for the validation test)"
          - "Every field defined in the schema has a corresponding entry in the example"
          - "No placeholder leaks through (no real client names, project IDs, or targets)"
      - id: B4
        title: Write .claude/skills/gcp-deploy/templates/tfvars.tmpl
        scope: |
          Terraform tfvars template the skill renders from deployment.yaml.
          Skill substitutes values from the YAML into this template to
          produce terraform.tfvars in the operator's deployment folder.
          The skill is responsible for the substitution logic (which it
          performs in shell or Python at runtime — Claude Code chooses
          based on what's available).
        files:
          - .claude/skills/gcp-deploy/templates/tfvars.tmpl
        content_requirements:
          - "Template uses unambiguous placeholder syntax (e.g., {{client_name}} or ${client_name}) that Claude Code can substitute reliably"
          - "Every Terraform module variable has a corresponding template entry"
          - "Header comment in the rendered output states the file was generated by the gcp-deploy skill and lists the source YAML path"
          - "Header warns operators not to edit the rendered file directly"
        acceptance:
          - "File exists"
          - "Template covers every variable declared in infra/gcp/variables.tf (cross-reference required at implementation time)"
          - "Rendered output (with a sample YAML substituted) passes `terraform fmt -check` and `terraform validate` when placed in a folder with the module"
      - id: B5
        title: Write .claude/skills/gcp-deploy/templates/main.tf.tmpl and backend.tf.tmpl
        scope: |
          Terraform entry-point template (module call) and backend
          configuration template, similar to B4 but covering the
          non-tfvars Terraform files. These are rendered into the
          operator's deployment folder alongside tfvars.
        files:
          - .claude/skills/gcp-deploy/templates/main.tf.tmpl
          - .claude/skills/gcp-deploy/templates/backend.tf.tmpl
        content_requirements:
          - "main.tf.tmpl references the infra/gcp/ module via relative path: source = \"../../infra/gcp\""
          - "main.tf.tmpl passes through all required variables from tfvars"
          - "backend.tf.tmpl uses the gcs backend with bucket name derived from gcp_project_id (e.g., ${gcp_project_id}-tfstate-leansecurity-nuclei to match the bootstrap script's bucket naming convention)"
          - "Both files include header comments stating skill-generated, do-not-edit"
        acceptance:
          - "Files exist"
          - "Rendered output validates with terraform init + terraform validate when run against a fresh deployment folder"
          - "The relative module path ../../infra/gcp correctly resolves from a deployments/<client>/ folder to the module location"
          - "Backend bucket name in backend.tf matches what scripts/bootstrap-gcp-client.sh creates"
      - id: B6
        title: Write .claude/commands/gcp-deploy.md
        scope: |
          Slash command wrapper. Thin file that, when /gcp-deploy is
          invoked, instructs Claude Code to load and execute the
          gcp-deploy skill against the current working directory. This
          provides the deterministic invocation path alongside intent
          triggering.
        files:
          - .claude/commands/gcp-deploy.md
        content_requirements:
          - "File follows the Claude Code slash command convention current at implementation time (verify the exact frontmatter and body format during implementation)"
          - "Command description states: 'Deploy the leansecurity-nuclei pipeline to GCP using the gcp-deploy skill'"
          - "Body instructs Claude Code to invoke the gcp-deploy skill, with the operator's current working directory as the target deployment folder"
        acceptance:
          - "File exists at .claude/commands/gcp-deploy.md"
          - "Invoking /gcp-deploy in a Claude Code session causes the gcp-deploy skill to load and run"
          - "If the Claude Code slash command convention differs from what this spec assumes, the deliverable adjusts the file location/format and documents the adjustment in the PR"

      - id: B7
        title: Update .gitignore
        scope: |
          Add the gitignore pattern that excludes per-client deployment
          folders while keeping _example/ committed. This is the
          structural protection against client artifacts leaking into
          the public repo.
        files:
          - .gitignore
        new_entries:
          - "deployments/*"
          - "!deployments/_example/"
          - "!deployments/_example/**"
        acceptance:
          - ".gitignore contains the three new entries"
          - "Creating a new file at deployments/foo/test.txt shows as ignored by git"
          - "Creating a new file at deployments/_example/test.txt shows as tracked by git"
          - "Existing files under deployments/_example/ remain tracked unchanged"

      - id: B8
        title: Write .claude/skills/gcp-deploy/README.md
        scope: |
          Skill-level README for humans (not Claude Code). Documents
          what the skill does, how operators invoke it, what files it
          reads and writes, and what its dependencies are. Linked from
          the main repo README and docs/setup-guide.md.
        files:
          - .claude/skills/gcp-deploy/README.md
        required_sections:
          - "Purpose (one paragraph)"
          - "How to invoke (both intent and slash command)"
          - "Prerequisites (gcloud, terraform, public repo checkout)"
          - "File layout (what the skill bundle contains)"
          - "Configuration (link to deployment.example.yaml)"
          - "Workflow overview (the 11 steps from SKILL.md, summarized)"
          - "What this skill does not do (out of scope clarifications)"
          - "See also (cross-links to setup guide, gcp_architecture.md, module README)"
        acceptance:
          - "File exists"
          - "All cross-links resolve"
          - "Renders correctly on GitHub markdown viewer"
          - "Reading this README alone, a new operator can understand whether the skill is right for them and where to start"

    workstream_acceptance:
      - "All deliverables B1-B8 acceptance criteria pass"
      - "Markdown lint passes on all markdown deliverables"
      - "JSON schema validates against itself (meta-schema check)"
      - "A test run-through using deployment.example.yaml (with placeholders replaced) renders valid tfvars/main.tf/backend.tf when subjected to the skill's documented substitution logic"

  # ════════════════════════════════════════════════════════════════════════
  # D. Documentation
  # ════════════════════════════════════════════════════════════════════════

  - id: documentation
    title: Documentation updates
    depends_on: [build]
    description: |
      Updates to existing documentation to reflect the new skill. The
      skill itself has its own README (deliverable B8); this workstream
      covers cross-references and integration points from existing docs.

    deliverables:

      - id: D1
        title: Update root README.md
        scope: |
          Add a section on the gcp-deploy skill. Describe both invocation
          paths (intent and slash command). Link to the skill README and
          to the setup guide. Should not duplicate content — just
          surface the skill's existence and point at the canonical docs.
        files:
          - README.md
        required_changes:
          - "New subsection under the cloud-automated mode section: 'Skill-assisted deployment'"
          - "One paragraph: what the skill is, who runs it, how to invoke"
          - "Cross-link to .claude/skills/gcp-deploy/README.md and docs/setup-guide.md"
        acceptance:
          - "README.md mentions the gcp-deploy skill in the cloud-mode section"
          - "Both invocation methods (intent + /gcp-deploy) are mentioned"
          - "Cross-links resolve"

      - id: D2
        title: Update docs/setup-guide.md
        scope: |
          Add an alternative "skill-assisted" path to the setup guide.
          Existing manual path (the one delivered in the predecessor
          feature) remains; the skill-assisted path is documented as
          the recommended starting point. The manual path becomes
          fallback for situations where the skill is unavailable or
          inappropriate.
        files:
          - docs/setup-guide.md
        required_changes:
          - "New section at the top: 'Quick start: using the gcp-deploy skill'"
          - "Step-by-step instructions for the skill-assisted path: clone the repo, cd to deployments/<your-client>/, invoke the skill, follow prompts"
          - "Existing manual setup path moves below, labeled 'Manual setup (alternative)'"
          - "Note that the manual path remains supported and may be necessary in restricted environments"
        acceptance:
          - "Skill-assisted path appears first and is labeled as the recommended approach"
          - "Manual path remains complete and accurate"
          - "Both paths reach the same end state"
          - "Cross-link to the skill README is present"

      - id: D3
        title: Update docs/gcp_architecture.md
        scope: |
          Add a brief note about the skill in the operating model
          section. Explain that the skill is an automation layer over
          the architecture, not a change to the architecture itself.
          The architecture document remains primarily about what is
          deployed and why; the skill is mentioned as a how.
        files:
          - docs/gcp_architecture.md
        required_changes:
          - "One paragraph in the operating model section noting the existence of the gcp-deploy skill"
          - "Clarification that the skill orchestrates the same Terraform module described in this document — it does not bypass or replace it"
          - "Cross-link to the skill README"
        acceptance:
          - "Architecture document mentions the skill once, briefly"
          - "Document still reads as primarily architectural, not operational"
          - "No duplication of skill workflow content"

    workstream_acceptance:
      - "D1-D3 acceptance criteria pass"
      - "All cross-references in the documentation point at existing files"

# ──────────────────────────────────────────────────────────────────────────────
# Out of scope
# ──────────────────────────────────────────────────────────────────────────────

out_of_scope:
  - "First scan trigger after terraform apply. The skill stops at apply complete; operator triggers the first scan manually."
  - "JSONL output verification. The skill does not verify scan output. Operators run their own validation post-deploy."
  - "Image rebuild. The skill does not build or push the scanner image. Images are produced by publish-image.yaml in CI and consumed by the skill via the GHCR URI."
  - "Module changes. The skill consumes the Terraform module as-is. If the module needs changes to support new deployment patterns, that is a module feature, not a skill feature."
  - "Multi-cloud abstraction. This skill is GCP only. AWS and Azure get their own skills (aws-deploy, azure-deploy) when those modules are built. No shared abstraction layer."
  - "CLI program with argument parser and exit codes. The skill is a runbook for Claude Code, not a polished program. scripts/deploy.sh is not in scope here."
  - "Backup or sync tooling for deployment.yaml or targets.txt. Operators are responsible for backing up their own intent files. The skill assumes those files exist locally when invoked."
  - "Re-implementing scripts/bootstrap-gcp-client.sh. The skill invokes the existing script; it does not replace or duplicate it."
  - "GCP project provisioning. The skill assumes a GCP project already exists and the operator has appropriate IAM. Project creation is upstream of the skill."

# ──────────────────────────────────────────────────────────────────────────────
# Sequencing
# ──────────────────────────────────────────────────────────────────────────────

sequencing:
  rule: "Workstreams execute sequentially. Documentation depends on build."
  order:
    - build
    - documentation
  rationale: |
    Documentation must reference the actual final shape of the skill,
    not a predicted shape. Cross-links and command names need to match
    what was actually delivered.

  predecessor_feature: gcp-cloud-deploy
  predecessor_requirement: |
    The gcp-cloud-deploy feature must be complete and merged before
    work on this feature begins. Specifically, the following artifacts
    must exist:
      - infra/gcp/ Terraform module with enable_scheduler, enable_wif,
        enable_ar_mirror flags implemented and tested
      - scripts/bootstrap-gcp-client.sh exists and is validated
      - deployments/_example/ exists with the GHCR-model tfvars shape
      - docs/setup-guide.md exists
      - .github/workflows/publish-image.yaml has produced at least one
        successful GHCR push (the skill's default image tag pins to
        something that exists)

# ──────────────────────────────────────────────────────────────────────────────
# Verification demarcation
# ──────────────────────────────────────────────────────────────────────────────

verification:
  claude_code_verified: |
    Most acceptance criteria are verifiable locally without cloud
    credentials: file existence, schema validity, markdown lint, JSON
    schema validation, template substitution dry runs against
    deployment.example.yaml, .gitignore behavior checks.

  architect_verified: |
    End-to-end skill invocation against a real GCP test project. The
    only way to verify the skill orchestrates correctly is to run it.
    Specifically:
      - Operator runs the skill from a fresh deployment folder, the
        skill scaffolds correctly from _example/
      - Operator populates deployment.yaml with valid test values, runs
        the skill, the skill renders correct tfvars
      - The skill runs terraform plan and produces a digestible summary
        that the architect agrees is operator-friendly
      - The skill runs terraform apply only after confirmation
      - Apply succeeds against the test GCP project (validating the
        rendered tfvars actually work)
      - Re-running the skill with the same YAML produces a clean plan
        (zero changes), confirming idempotency
      - Re-running with a modified YAML (e.g., enable_scheduler flipped)
        produces the expected delta in the plan
      - /gcp-deploy slash command invocation reaches the same skill

# ──────────────────────────────────────────────────────────────────────────────
# Inputs Claude Code requires
# ──────────────────────────────────────────────────────────────────────────────

inputs:
  - path: project repository (current state, post-gcp-cloud-deploy merge)
    purpose: "All file modifications and additions happen here"
    required: true
    notes: |
      The skill depends on artifacts from the gcp-cloud-deploy feature.
      Verify the predecessor feature's deliverables exist before
      starting this work.

  - path: Claude Code skill system documentation (current version)
    purpose: "Confirm the exact SKILL.md frontmatter format and slash command location"
    required: true
    notes: |
      The decisions_to_confirm section assumes .claude/skills/ and
      .claude/commands/ as the locations. If the Claude Code skill
      system has changed conventions since this spec was written, the
      implementation should follow current conventions and document
      the deviation.

# ──────────────────────────────────────────────────────────────────────────────
# Deliverable summary
# ──────────────────────────────────────────────────────────────────────────────

deliverable_summary:
  build:
    - ".claude/skills/gcp-deploy/SKILL.md (NEW)"
    - ".claude/skills/gcp-deploy/schema/deployment.schema.json (NEW)"
    - ".claude/skills/gcp-deploy/templates/deployment.example.yaml (NEW)"
    - ".claude/skills/gcp-deploy/templates/tfvars.tmpl (NEW)"
    - ".claude/skills/gcp-deploy/templates/main.tf.tmpl (NEW)"
    - ".claude/skills/gcp-deploy/templates/backend.tf.tmpl (NEW)"
    - ".claude/skills/gcp-deploy/README.md (NEW)"
    - ".claude/commands/gcp-deploy.md (NEW)"
    - ".gitignore (update — add deployments/* exclusion)"
  documentation:
    - "README.md (update — skill section)"
    - "docs/setup-guide.md (update — skill-assisted quickstart path)"
    - "docs/gcp_architecture.md (update — operating model note)" 