# Plan — move-profiles-to-deploy

## Summary

Move profiles.yaml from a single global path to a per-client deployment artifact.
`scan.py` will look for `deployments/<client>/profiles.yaml` first; if absent, fall back
to `scanner/profiles/profiles.yaml`. This enables per-client profile customization without
breaking Docker builds or GCP infra (which continue reading the global copy baked into the image).

---

## Assumption requiring architect confirmation

**Fallback vs. hard move**: The task says "move", implying the global file could be deleted.
However, `docker/Dockerfile.local` bakes in `scanner/` (including `scanner/profiles/`), and
`infra/gcp/main.tf` defaults `profiles_file` to `scanner/profiles/profiles.yaml`. Deleting the
global file breaks the container build and GCP upload without a separate change.

**Recommendation**: Keep the global file; make per-client override opt-in via lookup order.
Operators copy `scanner/_example/profiles.yaml` to `deployments/<client>/profiles.yaml` to
customize. No global file deletion in this task.

Confirm before I implement, or tell me to do a hard move (I'll update Docker + infra too).

---

## Deliverables

### 1. `scanner/_example/profiles.yaml` (new file)
Copy of the canonical 7-profile set. This is the template operators copy when setting up a
new client. Lives in `scanner/_example/` so it's tracked in git (unlike `deployments/` which
is fully gitignored).

### 2. `scanner/scan.py` — update `PROFILES_PATH` resolution
Replace the hardcoded module-level constant with a function that resolves the profile path
based on the client argument:

```python
def _resolve_profiles_path(client: str) -> Path:
    # Per-client override wins; global default is the fallback.
    client_profiles = REPO_ROOT / "deployments" / client / "profiles.yaml"
    if client_profiles.exists():
        return client_profiles
    return Path(__file__).resolve().parent / "profiles" / "profiles.yaml"
```

Called inside `main()` after `client` is parsed:
```python
profiles_path = _resolve_profiles_path(client)
profiles = load_profiles(str(profiles_path)).get("profiles", {})
```

The module-level `PROFILES_PATH` constant is removed (it was unused in calls already,
since `main()` is the sole caller and it can inline the resolution).

### 3. `tests/test_scan_profiles_path.py` (new test file)
New test module covering the lookup logic:

- `test_uses_client_profiles_when_present` — tmp_path with a `deployments/<client>/profiles.yaml`; assert `_resolve_profiles_path` returns that path.
- `test_falls_back_to_global_when_absent` — no client profiles.yaml; assert returns `scanner/profiles/profiles.yaml`.
- `test_scan_main_respects_client_profiles` — integration test: mock `load_profiles` and `shutil.which`; verify `scan.py`'s `main()` calls `load_profiles` with the client-local path when present.

### 4. `scanner/_example/README.md` — update
Add a line noting that `profiles.yaml` can be copied to `deployments/<client>/profiles.yaml`
to customize scan behavior for that client. One sentence, no prose bloat.

---

## Files changed

| File | Change |
|------|--------|
| `scanner/scan.py` | Replace module-level `PROFILES_PATH` with `_resolve_profiles_path(client)` called in `main()` |
| `scanner/_example/profiles.yaml` | New — 7-profile template (copy of `scanner/profiles/profiles.yaml`) |
| `scanner/_example/README.md` | Update — add one line about profiles.yaml override |
| `tests/test_scan_profiles_path.py` | New — 3 tests covering lookup behavior |

---

## Files NOT changed

| File | Reason |
|------|--------|
| `scanner/profiles/profiles.yaml` | Preserved as global default + Docker build source |
| `docker/Dockerfile.local` | No change; bakes `scanner/` including global profiles |
| `infra/gcp/main.tf` | No change; `profiles_file` variable still defaults to global path |
| `scanner/nuclei_helpers.py` | `load_profiles(path)` already accepts arbitrary path |
| `scanner/validate_profiles.py` | Already accepts `--profiles-file` flag |
| All existing tests | Existing tests use mock YAML, not the real profiles path |

---

## Verification

```bash
poetry run black --check .
poetry run ruff check .
poetry run bandit -r . --severity-level high
poetry run pytest
```

All four must pass before this task is considered complete.

---

## Out of scope

- Docker or GCP infra changes
- Per-client profile content — operators provide their own
- Removing `scanner/profiles/profiles.yaml`
- `nuclei_convert_tool.py` or `validate_profiles.py` changes
