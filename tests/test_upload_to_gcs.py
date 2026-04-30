# Unit tests for scanner/upload_to_gcs.py

# Standard Library Modules
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

# scanner/ is not a package, so add it to sys.path before importing — same
# pattern used by test_nuclei_helpers.py and the scanner CLIs themselves.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scanner"))
import upload_to_gcs  # noqa: E402

# ---------- helpers ----------


def _setup_client(tmp_path: Path, env_lines: list[str], month: str = "2026-04") -> Path:
    """Build a temp REPO_ROOT with deployments/<client>/.env and results/<client>/<month>/.

    Returns the temp root so callers can monkeypatch upload_to_gcs.REPO_ROOT.
    Each test gets its own fixture tree to keep them independent.
    """

    # Lay out the deployments/<client>/ tree and write the supplied env content.
    client_dir = tmp_path / "deployments" / "acme"
    client_dir.mkdir(parents=True)
    (client_dir / ".env").write_text("\n".join(env_lines) + "\n", encoding="utf-8")

    # Lay out a sibling results/<client>/<month>/ tree with two stub jsonl files
    # so happy-path tests can assert the argv expansion.
    results_dir = tmp_path / "results" / "acme" / month
    results_dir.mkdir(parents=True)
    (results_dir / "baseline.jsonl").write_text('{"a":1}\n', encoding="utf-8")
    (results_dir / "patch.jsonl").write_text('{"b":2}\n', encoding="utf-8")
    return tmp_path


# ---------- load_env ----------


def test_load_env_parses_basic_keys(tmp_path):
    """Plain KEY=VALUE pairs round-trip into a dict."""

    # Write a small env file with comments, blank lines, and quoted values to
    # confirm the parser handles each form.
    env = tmp_path / ".env"
    env.write_text(
        "# comment\n\nGCP_PROJECT=my-project\nGCS_BUCKET='gs://b'\nGCS_PREFIX=\"nuclei\"\n",
        encoding="utf-8",
    )
    parsed = upload_to_gcs.load_env(env)
    assert parsed == {"GCP_PROJECT": "my-project", "GCS_BUCKET": "gs://b", "GCS_PREFIX": "nuclei"}


def test_load_env_missing_file_exits(tmp_path):
    """Missing .env triggers a clear SystemExit, not FileNotFoundError."""

    # Point at a path that doesn't exist; load_env should sys.exit with a hint.
    with pytest.raises(SystemExit, match="not found"):
        upload_to_gcs.load_env(tmp_path / "nope.env")


def test_load_env_malformed_line_exits(tmp_path):
    """A line without '=' is a typo and should fail loud, not silently skip."""

    # Single bad line should abort parsing.
    env = tmp_path / ".env"
    env.write_text("GCP_PROJECT=ok\nbogusline\n", encoding="utf-8")
    with pytest.raises(SystemExit, match="malformed"):
        upload_to_gcs.load_env(env)


# ---------- check_gcloud_authenticated ----------


def test_check_gcloud_authenticated_returns_account():
    """Active account in stdout flows back to the caller."""

    # subprocess.run is mocked to simulate a logged-in user.
    fake = subprocess.CompletedProcess(args=[], returncode=0, stdout="user@example.com\n", stderr="")
    with patch.object(upload_to_gcs.subprocess, "run", return_value=fake):
        assert upload_to_gcs.check_gcloud_authenticated() == "user@example.com"


def test_check_gcloud_authenticated_empty_exits():
    """Empty stdout = no active account → SystemExit with the login hint."""

    # subprocess.run mocked to return empty stdout (no active session).
    fake = subprocess.CompletedProcess(args=[], returncode=0, stdout="\n", stderr="")
    with patch.object(upload_to_gcs.subprocess, "run", return_value=fake):
        with pytest.raises(SystemExit, match="gcloud auth login"):
            upload_to_gcs.check_gcloud_authenticated()


# ---------- build_upload_cmd ----------


def test_build_upload_cmd_argv_shape(tmp_path):
    """Each source file becomes an explicit argv entry; destination is last."""

    # Two stub paths + a destination URI; verify shell-free argv layout.
    files = [tmp_path / "a.jsonl", tmp_path / "b.jsonl"]
    cmd = upload_to_gcs.build_upload_cmd(files, "gs://bucket/nuclei/2026-04/")
    assert cmd == [
        "gcloud",
        "storage",
        "cp",
        str(files[0]),
        str(files[1]),
        "gs://bucket/nuclei/2026-04/",
    ]


# ---------- main: integration via mocks ----------


def test_main_happy_path_invokes_gcloud(tmp_path, monkeypatch, capsys):
    """End-to-end happy path runs preflight + upload with the right argv."""

    # Build the temp repo tree with a valid .env and two jsonl files.
    root = _setup_client(
        tmp_path,
        ["GCP_PROJECT=acme-prj", "GCS_BUCKET=gs://acme-security-scans"],
    )
    monkeypatch.setattr(upload_to_gcs, "REPO_ROOT", root)
    # gcloud must appear installed for the preflight to pass.
    monkeypatch.setattr(upload_to_gcs.shutil, "which", lambda _binary: "/usr/bin/gcloud")

    # Capture every subprocess.run invocation so we can assert auth probe,
    # project pin, and upload all happen in the right order with the right argv.
    calls = []

    def fake_run(cmd, **kwargs):
        calls.append((tuple(cmd), kwargs))
        # First call is the auth-list probe; return a logged-in account.
        if cmd[:3] == ["gcloud", "auth", "list"]:
            return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="me@example.com\n", stderr="")
        return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(upload_to_gcs.subprocess, "run", fake_run)

    upload_to_gcs.main(["acme", "--month", "2026-04"])

    # Three subprocess calls expected: auth list, config set project, storage cp.
    assert len(calls) == 3
    assert calls[0][0][:3] == ("gcloud", "auth", "list")
    assert calls[1][0] == ("gcloud", "config", "set", "project", "acme-prj")
    upload = calls[2][0]
    assert upload[:3] == ("gcloud", "storage", "cp")
    assert upload[-1] == "gs://acme-security-scans/nuclei/2026-04/"
    # Both jsonl files made it into the argv (order is sorted-by-name).
    assert any(p.endswith("baseline.jsonl") for p in upload)
    assert any(p.endswith("patch.jsonl") for p in upload)

    # Summary line should mention the destination so operators can spot-check.
    out = capsys.readouterr().out
    assert "gs://acme-security-scans/nuclei/2026-04/" in out


def test_main_dry_run_skips_upload(tmp_path, monkeypatch, capsys):
    """--dry-run prints the plan but does not invoke `gcloud config set` or upload."""

    # Same fixture as the happy path, but pass --dry-run.
    root = _setup_client(
        tmp_path,
        ["GCP_PROJECT=acme-prj", "GCS_BUCKET=gs://acme-security-scans"],
    )
    monkeypatch.setattr(upload_to_gcs, "REPO_ROOT", root)
    monkeypatch.setattr(upload_to_gcs.shutil, "which", lambda _binary: "/usr/bin/gcloud")

    # Track every subprocess.run; in dry-run only the auth probe should fire.
    calls = []

    def fake_run(cmd, **kwargs):
        calls.append(tuple(cmd))
        if cmd[:3] == ["gcloud", "auth", "list"]:
            return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="me@example.com\n", stderr="")
        return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(upload_to_gcs.subprocess, "run", fake_run)

    upload_to_gcs.main(["acme", "--month", "2026-04", "--dry-run"])

    # Only the auth list probe should have been called — no project pin, no upload.
    assert len(calls) == 1
    assert calls[0][:3] == ("gcloud", "auth", "list")
    out = capsys.readouterr().out
    assert "Dry run" in out


def test_main_missing_env_key_exits(tmp_path, monkeypatch):
    """An .env with no GCS_BUCKET aborts before any gcloud call."""

    # Build env that only declares GCP_PROJECT — GCS_BUCKET is missing.
    root = _setup_client(tmp_path, ["GCP_PROJECT=acme-prj"])
    monkeypatch.setattr(upload_to_gcs, "REPO_ROOT", root)

    with pytest.raises(SystemExit, match="GCS_BUCKET"):
        upload_to_gcs.main(["acme", "--month", "2026-04"])


def test_main_bad_bucket_scheme_exits(tmp_path, monkeypatch):
    """GCS_BUCKET that doesn't start with gs:// is a typo, fail fast."""

    # Wrong scheme should be rejected before any subprocess work.
    root = _setup_client(
        tmp_path,
        ["GCP_PROJECT=acme-prj", "GCS_BUCKET=acme-security-scans"],
    )
    monkeypatch.setattr(upload_to_gcs, "REPO_ROOT", root)

    with pytest.raises(SystemExit, match="gs://"):
        upload_to_gcs.main(["acme", "--month", "2026-04"])


def test_main_empty_results_dir_exits(tmp_path, monkeypatch):
    """No jsonl files in the month dir → exit before talking to gcloud."""

    # Set up env, then clear out the seeded jsonl files so the dir is empty.
    root = _setup_client(
        tmp_path,
        ["GCP_PROJECT=acme-prj", "GCS_BUCKET=gs://acme-security-scans"],
    )
    for f in (root / "results" / "acme" / "2026-04").glob("*.jsonl"):
        f.unlink()
    monkeypatch.setattr(upload_to_gcs, "REPO_ROOT", root)

    with pytest.raises(SystemExit, match="no \\*.jsonl"):
        upload_to_gcs.main(["acme", "--month", "2026-04"])


def test_main_no_active_auth_exits(tmp_path, monkeypatch):
    """Empty `gcloud auth list` output → exit with login hint, no upload."""

    # Valid env + jsonl files, but gcloud reports no active account.
    root = _setup_client(
        tmp_path,
        ["GCP_PROJECT=acme-prj", "GCS_BUCKET=gs://acme-security-scans"],
    )
    monkeypatch.setattr(upload_to_gcs, "REPO_ROOT", root)
    monkeypatch.setattr(upload_to_gcs.shutil, "which", lambda _binary: "/usr/bin/gcloud")

    # All subprocess calls return empty stdout, simulating "not logged in".
    def fake_run(cmd, **kwargs):
        return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(upload_to_gcs.subprocess, "run", fake_run)

    with pytest.raises(SystemExit, match="gcloud auth login"):
        upload_to_gcs.main(["acme", "--month", "2026-04"])
