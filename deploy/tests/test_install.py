"""Installer contract tests; no Docker daemon, network, or Tailscale account required."""

import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


DEPLOY = Path(__file__).resolve().parents[1]
MOCK_TOOL = r"""#!/usr/bin/env python3
import json
import os
from pathlib import Path
import secrets
import shutil
import sys

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(json.dumps([tool, *args]) + "\n")

if tool == "curl":
    url = next(arg for arg in args if arg.startswith(("https://", "http://")))
    if url.startswith("http://"):
        if os.getenv("FAIL_HEALTH") or url != "http://127.0.0.1:" + os.getenv("MOCK_PORT", "8080") + "/health":
            sys.exit(22)
        print("Healthy", end="")
    else:
        path = url.split("/deploy/", 1)[1]
        if path == os.getenv("FAIL_DOWNLOAD"):
            sys.exit(22)
        shutil.copyfile(Path(os.environ["MOCK_DEPLOY"]) / path, args[args.index("-o") + 1])
elif tool == "docker":
    if args == ["info"]:
        sys.exit(1 if os.getenv("FAIL_DOCKER") or (os.getenv("REQUIRE_SUDO") and not os.getenv("MOCK_SUDO")) else 0)
    if args == ["compose", "port", "netns", "8080"]:
        print("127.0.0.1:" + os.getenv("MOCK_PORT", "8080"))
    elif args[:4] == ["compose", "exec", "-T", "tailscale"]:
        if args[4:] == ["tailscale", "serve", "status"]:
            print("No serve config" if os.getenv("FAIL_TAILSCALE") else "https://bankofdad.test.ts.net (tailnet only)\n|-- / proxy http://127.0.0.1:8080")
        else:
            print(json.dumps({"Self": {"DNSName": "" if os.getenv("FAIL_TAILSCALE") else "bankofdad.test.ts.net."}}))
elif tool == "sudo":
    os.environ["MOCK_SUDO"] = "1"
    os.execvp(args[0], args)
elif tool == "openssl":
    if os.getenv("FAIL_RANDOM"):
        sys.exit(1)
    print(secrets.token_hex(32))
elif tool != "sleep":
    sys.exit("Unexpected mock tool: " + tool)
"""


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bankofdad-installer-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.install = self.root / "install with spaces"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("curl", "docker", "sudo", "openssl", "sleep"):
            tool = self.bin / name
            tool.write_text(MOCK_TOOL)
            tool.chmod(0o755)
        self.log = self.root / "calls.jsonl"
        self.env = {
            **os.environ,
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "BANKOFDAD_DIR": str(self.install),
            "BANKOFDAD_REF": "test-ref",
            "TS_AUTHKEY": "tskey-test-not-a-real-key",
            "TS_HOSTNAME": "bankofdad-test",
            "TS_EXTRA_ARGS": "--advertise-tags=tag:bankofdad",
            "MOCK_LOG": str(self.log),
            "MOCK_DEPLOY": str(DEPLOY),
        }
        self.script = (DEPLOY / "install.sh").read_bytes().decode()
        self.assertNotIn("\r", self.script, "The curl-able script must use LF line endings.")

    def run_installer(self, script=None, **options):
        env = self.env.copy()
        for key, value in options.items():
            if value is None:
                env.pop(key, None)
            else:
                env[key] = value
        return subprocess.run(
            ["bash"], input=self.script if script is None else script,
            text=True, capture_output=True, env=env, start_new_session=True, timeout=15,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def existing_env(self, content="POSTGRES_PASSWORD=keep-this\nJWT_SIGNING_KEY=keep-this-too\n"):
        self.install.mkdir(parents=True)
        env = self.install / ".env"
        env.write_text(content)
        return env

    def test_fresh_piped_install(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        env = self.install / ".env"
        content = env.read_text()
        self.assertEqual(stat.S_IMODE(env.stat().st_mode), 0o600)
        self.assertRegex(content, r"POSTGRES_PASSWORD=[a-f0-9]{64}\n")
        self.assertRegex(content, r"JWT_SIGNING_KEY=[a-f0-9]{64}\n")
        self.assertIn("TS_HOSTNAME=bankofdad-test\n", content)
        self.assertIn("TS_EXTRA_ARGS=--advertise-tags=tag:bankofdad\n", content)
        self.assertNotIn(self.env["TS_AUTHKEY"], result.stdout + result.stderr)
        self.assertIn("https://bankofdad.test.ts.net/health", result.stdout)
        self.assertIn("API_BASE_URL = https:/$()/bankofdad.test.ts.net", result.stdout)
        self.assertEqual((self.install / "docker-compose.yml").read_bytes(), (DEPLOY / "docker-compose.yml").read_bytes())
        self.assertTrue(any("test-ref/deploy/" in str(call) for call in self.calls()))

    def test_rerun_preserves_env_without_optional_port(self):
        env = self.existing_env()
        before = env.read_bytes()
        result = self.run_installer(TS_AUTHKEY=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(env.read_bytes(), before)

    def test_uses_actual_published_port(self):
        result = self.run_installer(MOCK_PORT="9090")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("http://127.0.0.1:9090/health", result.stdout)

    def test_does_not_remove_other_services(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any("--remove-orphans" in call for call in self.calls()))

    def test_existing_empty_env_is_not_overwritten(self):
        env = self.existing_env("")
        env.chmod(0o644)
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(env.read_bytes(), b"")
        self.assertFalse(any(call[:3] == ["docker", "compose", "up"] for call in self.calls()))

    def test_failed_download_preserves_existing_bundle(self):
        self.existing_env()
        compose = self.install / "docker-compose.yml"
        compose.write_text("existing compose\n")
        result = self.run_installer(FAIL_DOWNLOAD="tailscale/serve.json")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(compose.read_text(), "existing compose\n")
        self.assertFalse(any(call[:3] == ["docker", "compose", "up"] for call in self.calls()))
        self.assertEqual(list(self.install.glob(".install.*")), [])

    def test_failed_random_generation_leaves_no_env(self):
        result = self.run_installer(FAIL_RANDOM="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.install / ".env").exists())

    def test_missing_terminal_leaves_no_env(self):
        result = self.run_installer(TS_AUTHKEY=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no terminal", result.stderr)
        self.assertFalse((self.install / ".env").exists())

    def test_unhealthy_api_fails_with_bounded_requests(self):
        result = self.run_installer(FAIL_HEALTH="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not healthy", result.stderr)
        self.assertNotIn("Done.", result.stdout)
        requests = [call for call in self.calls() if call[0] == "curl" and any(arg.startswith("http://") for arg in call)]
        self.assertTrue(requests)
        self.assertTrue(all("--max-time" in call for call in requests))

    def test_missing_tailscale_serve_fails(self):
        result = self.run_installer(FAIL_TAILSCALE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Done.", result.stdout)

    def test_docker_down_does_not_write_files(self):
        result = self.run_installer(FAIL_DOCKER="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.install.exists())

    def test_sudo_docker_fallback(self):
        result = self.run_installer(REQUIRE_SUDO="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["sudo", "docker", "compose", "up", "-d"], self.calls())

    def test_script_without_final_main_does_nothing(self):
        result = self.run_installer(script=self.script.rsplit('\nmain "$@"', 1)[0])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.install.exists())

    def test_relative_install_directory_cleans_up(self):
        relative = os.path.relpath(self.install)
        result = self.run_installer(BANKOFDAD_DIR=relative)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list(self.install.glob(".install.*")), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
