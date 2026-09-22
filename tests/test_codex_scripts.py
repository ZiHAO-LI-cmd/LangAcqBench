"""Offline orchestration tests; no Apptainer, Slurm, GPU or API calls required.

Run: python3 -m unittest discover -s tests -v
On Windows, set TEST_BASH to the Git Bash executable.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
BASH = os.environ.get("TEST_BASH", "bash")


def shell_path(path):
    value = Path(path).resolve().as_posix()
    if os.name == "nt":
        return "/" + value[0].lower() + value[2:]
    return value


class ScriptsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix=".test-codex-", dir=REPO)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copytree(REPO / "scripts", self.root / "scripts")
        for name in ("prompt.md", "evaluate.py", "timer.sh"):
            shutil.copyfile(REPO / name, self.root / name)
        shutil.copytree(REPO / "configs", self.root / "configs")
        for script in list((self.root / "scripts").glob("*.sh")) + [self.root / "timer.sh"]:
            script.write_text(script.read_text(), newline="\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        root = shell_path(self.root)
        (self.root / "env.sh").write_text(
            f'export PROJECT_ROOT="{root}"\n'
            f'export TMPDIR="{root}/tmp"\n'
            f'export HF_HOME="{root}/hf"\n'
            'mkdir -p "$TMPDIR" "$HF_HOME"\n', encoding="utf-8", newline="\n")
        self.stub("python3", f'exec "{shell_path(sys.executable)}" "$@"')
        self.stub("srun", 'exec "$@"')
        # Mock lock acquisition; actual cross-process flock is a cluster check.
        self.stub("flock", 'exit "${MOCK_LOCK_STATUS:-0}"')
        self.stub("apptainer", '''printf '%s\\n' "$@" > "$PROJECT_ROOT/argv.txt"
if [[ " ${*} " == *" codex exec "* ]]; then
    cat > "$PROJECT_ROOT/stdin.txt"
    printf '{"token":"refreshed"}\\n' > "$RUN_DIR/home/.codex/auth.json"
    exit "${MOCK_AGENT_STATUS:-0}"
fi
''')
        auth = self.root / "interactive/codex/home/.codex"
        auth.mkdir(parents=True)
        (auth / "auth.json").write_text('{"token":"original"}')
        self.env = dict(os.environ)
        for key in ("AGENT", "RUN_DIR", "USE_GPU", "SLURM_JOB_ID"):
            self.env.pop(key, None)
        self.env.update(SLURM_SUBMIT_DIR=root, SLURM_JOB_ID="123",
                        SLURM_JOB_END_TIME="4102444800")

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -eu\n" + body + "\n", encoding="utf-8", newline="\n")
        path.chmod(0o755)

    def run_script(self, script, *args, **env):
        environment = self.env | env
        return subprocess.run(
            [BASH, "-c", f'export PATH="{shell_path(self.bin)}:/usr/bin:/bin:$PATH"; '
             'exec bash "$@"', "test", shell_path(self.root / script), *args],
            env=environment, text=True, encoding="utf-8", errors="replace", capture_output=True)

    def argv(self):
        return (self.root / "argv.txt").read_text().splitlines()

    def test_opencode_default_unchanged(self):
        result = self.run_script("scripts/in-container.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.argv()
        self.assertEqual(args[-1], "opencode")
        self.assertTrue(args[-2].endswith("/containers/opencode.sif"))
        self.assertIn(shell_path(self.root) + "/interactive/home:/home/agent", args)

    def test_codex_selection_gpu_and_custom_command(self):
        result = self.run_script("scripts/in-container.sh", "python3", "--version",
                                 AGENT="codex", USE_GPU="1", CUDA_VISIBLE_DEVICES="2")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.argv()
        self.assertEqual(args[-2:], ["python3", "--version"])
        self.assertIn("--nv", args)
        self.assertIn("CUDA_VISIBLE_DEVICES=2", args)
        self.assertIn(shell_path(self.root) + "/containers/codex.sif", args)
        self.assertIn(shell_path(self.root) + "/interactive/codex/home:/home/agent", args)

    def test_invalid_agent_fails(self):
        self.assertEqual(self.run_script("scripts/in-container.sh", AGENT="../bad").returncode, 2)
        self.assertFalse((self.root / "argv.txt").exists())

    def test_batch_prompt_refresh_and_failure_status(self):
        result = self.run_script("scripts/codex.sh", "test-model",
                                 "configs/smollm3-swedish.example.json", MOCK_AGENT_STATUS="7")
        self.assertEqual(result.returncode, 7, result.stderr)
        run = self.root / "runs/codex-123"
        self.assertEqual((self.root / "stdin.txt").read_text(),
                         (run / "work/prompt.md").read_text())
        self.assertTrue((run / "work/evaluate.py").exists())
        auth = self.root / "interactive/codex/home/.codex/auth.json"
        self.assertEqual(json.loads(auth.read_text())["token"], "refreshed")
        self.assertIn("--skip-git-repo-check", self.argv())
        self.assertEqual(self.argv()[-1], "-")

    def test_lock_failure_does_not_start_agent(self):
        result = self.run_script("scripts/codex.sh", "test-model",
                                 "configs/smollm3-swedish.example.json", MOCK_LOCK_STATUS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "argv.txt").exists())
        auth = self.root / "interactive/codex/home/.codex/auth.json"
        self.assertEqual(json.loads(auth.read_text())["token"], "original")

    def test_missing_auth_fails_before_agent(self):
        (self.root / "interactive/codex/home/.codex/auth.json").unlink()
        result = self.run_script("scripts/codex.sh", "test-model",
                                 "configs/smollm3-swedish.example.json")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "argv.txt").exists())


if __name__ == "__main__":
    unittest.main()
