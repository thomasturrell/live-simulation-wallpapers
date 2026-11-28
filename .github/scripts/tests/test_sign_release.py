"""Exercise release failure gates without an Apple identity or network access.

Run on macOS: python3 -m unittest discover -s .github/scripts/tests -v
"""

import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / ".github/scripts/sign-release.sh"
PACKAGES = (
    ("Game-of-Life", "Game of Life Wallpaper.app", "LifeWallpaper"),
    ("City-Simulation", "City Simulation Wallpaper.app", "CityWallpaper"),
    ("System-Design", "System Design Wallpaper.app", "DesignWallpaper"),
)

# System tools that require real Apple credentials are replaced; ditto, zipfile,
# plistlib, jq and the shell run normally to check the actual packaging path.
MOCK = r'''
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

command = Path(sys.argv[0]).name
args = sys.argv[1:]
failure = os.environ.get("RELEASE_TEST_FAILURE", "")
with open(os.environ["RELEASE_TEST_LOG"], "a") as stream:
    stream.write(json.dumps([command] + args) + "\n")
if command == "codesign" and "--verify" in args and "-R" in args:
    subprocess.run(["/usr/bin/csreq", "-r", args[args.index("-R") + 1], "-t"], check=True, capture_output=True)
if command == "security":
    if args[0] == "create-keychain":
        Path(args[-1]).touch()
    elif args[0] == "import" and failure == "import":
        sys.exit(1)
    elif args[0] == "delete-keychain":
        if failure == "cleanup":
            sys.exit(1)
        Path(args[-1]).unlink()
    elif args[0] == "find-identity":
        team = "WRONGTEAM1" if failure == "identity" else "ABC1234567"
        print('1) ' + 'A' * 40 + ' "Developer ID Application: Test (' + team + ')"')
elif command == "codesign" and "--display" in args:
    if "--entitlements" in args:
        entitlements = {"com.apple.security.app-sandbox": True} if args[-1].endswith(".appex") else {}
        if failure == "entitlements":
            entitlements["com.apple.security.get-task-allow"] = True
        sys.stdout.buffer.write(plistlib.dumps(entitlements))
    else:
        if failure != "runtime":
            print("flags=0x10000(runtime)", file=sys.stderr)
        if failure != "timestamp":
            print("Timestamp=Test timestamp", file=sys.stderr)
elif command == "codesign" and failure == "signature" and "--verify" in args:
    sys.exit(1)
elif command == "xcrun":
    if args[:2] == ["notarytool", "store-credentials"] and failure == "credentials":
        print("Error: HTTP status code: 401. Invalid credentials.")
        for name, value in os.environ.items():
            if name.startswith("APPLE_"):
                print(name + "=" + value, file=sys.stderr)
        print("::error::untrusted workflow annotation", file=sys.stderr)
        sys.exit(1)
    elif args[:2] == ["notarytool", "submit"]:
        status = "Invalid" if failure == "rejected" else "Accepted"
        print(json.dumps({"id": "test-submission", "status": status}))
        if failure == "timeout":
            sys.exit(1)
    elif args[:2] == ["notarytool", "log"]:
        Path(args[-1]).write_text(json.dumps({"status": "Accepted", "issues": None}))
    elif args[:2] == ["stapler", "staple"]:
        if failure == "staple":
            sys.exit(1)
        (Path(args[-1]) / "Contents/stapled-ticket").touch()
    elif args[:2] == ["stapler", "validate"]:
        if not (Path(args[-1]) / "Contents/stapled-ticket").exists():
            sys.exit(1)
elif command == "spctl":
    if failure == "gatekeeper" and "City Simulation" in args[-1]:
        sys.exit(1)
    if failure == "extracted" and "verify-" in args[-1]:
        sys.exit(1)
elif command == "lipo":
    if len(args) != 3 or not Path(args[0]).is_file() or args[1] != "-verify_arch" or args[2] not in ("arm64", "x86_64"):
        sys.exit("Invalid lipo arguments")
    if failure == "architecture":
        sys.exit(1)
elif command == "file":
    print("Mach-O universal binary" if Path(args[-1]).read_bytes().startswith(b"Mach-O") else "data")
'''


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.runner = self.directory / "runner"
        self.runner.mkdir()
        self.unsigned = self.runner / "unsigned-assets"
        self.unsigned.mkdir()
        self.log = self.directory / "commands.jsonl"
        mock_bin = self.directory / "bin"
        mock_bin.mkdir()
        for command in ("security", "xcrun", "codesign", "lipo", "spctl", "file"):
            path = mock_bin / command
            path.write_text("#!" + sys.executable + "\n" + MOCK)
            path.chmod(0o755)
        self.env = dict(
            os.environ,
            PATH=str(mock_bin) + os.pathsep + os.environ["PATH"],
            RUNNER_TEMP=str(self.runner),
            RELEASE_TEST_LOG=str(self.log),
            APPLE_CERTIFICATE_BASE64=base64.b64encode(b"test-certificate").decode(),
            APPLE_CERTIFICATE_PASSWORD="test-export-password",
            APPLE_ID="test-apple-id@example.invalid",
            APPLE_TEAM_ID="ABC1234567",
            APPLE_APP_SPECIFIC_PASSWORD="test-app-specific-password",
            RELEASE_HAS_SYSTEM_DESIGN="true",
        )
        for name, app, extension in PACKAGES:
            with zipfile.ZipFile(self.unsigned / (name + "-Native-Wallpaper.zip"), "w") as archive:
                archive.writestr(app + "/Contents/MacOS/InstallWallpaper", b"Mach-O host")
                archive.writestr(app + "/Contents/Extensions/" + extension + ".appex/Contents/MacOS/" + extension, b"Mach-O extension")
                archive.writestr("INSTALL.md" if name == "Game-of-Life" else "README.md", "Install instructions")
                archive.writestr("LICENSE", "License text")
                if name != "Game-of-Life":
                    archive.writestr("assets/example.png", b"image fixture")

    def run_signing(self, failure=""):
        self.env["RELEASE_TEST_FAILURE"] = failure
        result = subprocess.run(["bash", str(SCRIPT)], cwd=ROOT, env=self.env,
                                capture_output=True, text=True)
        self.assertFalse((self.runner / "wallpaper-signing").exists())
        for name in ("APPLE_CERTIFICATE_BASE64", "APPLE_CERTIFICATE_PASSWORD", "APPLE_ID", "APPLE_TEAM_ID", "APPLE_APP_SPECIFIC_PASSWORD"):
            for value in {self.env.get(name, ""), self.env.get(name, "").strip()} - {""}:
                self.assertNotIn(value, result.stdout + result.stderr)
        return result

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_signs_all_three_inside_out_and_repackages_stapled_apps(self):
        result = self.run_signing()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        commands = self.commands()
        signing = [command for command in commands if command[:2] == ["codesign", "--force"]]
        self.assertEqual(len(signing), 6)
        for extension, app in zip(signing[::2], signing[1::2]):
            self.assertTrue(extension[-1].endswith(".appex"))
            self.assertTrue(app[-1].endswith(".app"))
            self.assertIn("--entitlements", extension)
            self.assertNotIn("--entitlements", app)
            for command in (extension, app):
                for flag in ("--keychain", "runtime", "--timestamp"):
                    self.assertIn(flag, command)
                self.assertNotIn("--deep", command)
        self.assertEqual(sum(command[:3] == ["xcrun", "notarytool", "submit"] for command in commands), 3)
        self.assertEqual(sum(command[0] == "spctl" for command in commands), 6)
        for name, app, _ in PACKAGES:
            with zipfile.ZipFile(self.runner / "release-assets" / (name + "-Native-Wallpaper.zip")) as archive:
                self.assertIn(app + "/Contents/stapled-ticket", archive.namelist())
                self.assertEqual(archive.read("LICENSE"), b"License text")
                if name != "Game-of-Life":
                    self.assertEqual(archive.read("assets/example.png"), b"image fixture")
        self.assertEqual(commands[-1][0:2], ["security", "delete-keychain"])

    def test_keeps_two_wallpaper_historical_tags_supported(self):
        self.env["RELEASE_HAS_SYSTEM_DESIGN"] = "false"
        result = self.run_signing()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(list((self.runner / "release-assets").glob("*.zip"))), 2)

    def test_trims_pasted_notary_credentials_without_changing_export_password(self):
        for name in ("APPLE_ID", "APPLE_TEAM_ID", "APPLE_APP_SPECIFIC_PASSWORD"):
            self.env[name] = " \t" + self.env[name] + "\r\n"
        self.env["APPLE_CERTIFICATE_PASSWORD"] = " password with intentional spaces "
        result = self.run_signing()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        credentials = next(command for command in self.commands() if command[:3] == ["xcrun", "notarytool", "store-credentials"])
        for flag, name in (("--apple-id", "APPLE_ID"), ("--team-id", "APPLE_TEAM_ID"), ("--password", "APPLE_APP_SPECIFIC_PASSWORD")):
            self.assertEqual(credentials[credentials.index(flag) + 1], self.env[name].strip())
        imported = next(command for command in self.commands() if command[:2] == ["security", "import"])
        self.assertEqual(imported[imported.index("-P") + 1], self.env["APPLE_CERTIFICATE_PASSWORD"])

    def test_credential_failure_retains_diagnostics_and_redacts_secrets(self):
        for name in ("APPLE_ID", "APPLE_TEAM_ID", "APPLE_APP_SPECIFIC_PASSWORD"):
            self.env[name] += "\n"
        result = self.run_signing("credentials")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HTTP status code: 401. Invalid credentials.", result.stdout)
        self.assertIn("[REDACTED]", result.stdout)
        self.assertIn("notarytool: ::error::untrusted workflow annotation", result.stdout)
        self.assertNotIn("\n::error::untrusted workflow annotation", result.stdout)
        self.assertFalse((self.runner / "release-assets").exists())
        self.assertEqual(self.commands()[-1][:2], ["security", "delete-keychain"])
        self.assertFalse(any(command[:3] == ["xcrun", "notarytool", "submit"] for command in self.commands()))

    def test_failures_remove_all_outputs_and_credentials(self):
        for failure in ("import", "identity", "architecture", "signature", "runtime", "timestamp", "entitlements", "rejected", "timeout", "staple", "gatekeeper", "extracted", "cleanup"):
            with self.subTest(failure=failure):
                result = self.run_signing(failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.runner / "release-assets").exists())

    def test_refuses_archive_path_traversal(self):
        archive = self.unsigned / "Game-of-Life-Native-Wallpaper.zip"
        with zipfile.ZipFile(archive, "a") as package:
            package.writestr("../outside", "untrusted")
        result = self.run_signing()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.runner / "outside").exists())
        self.assertFalse((self.runner / "release-assets").exists())

    def test_refuses_new_nested_code(self):
        archive = self.unsigned / "Game-of-Life-Native-Wallpaper.zip"
        with zipfile.ZipFile(archive, "a") as package:
            package.writestr(PACKAGES[0][1] + "/Contents/Frameworks/Unexpected.dylib", b"Mach-O helper")
        result = self.run_signing()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unexpected nested code", result.stdout)

    def test_missing_secrets_fail_before_creating_a_keychain(self):
        del self.env["APPLE_TEAM_ID"]
        result = self.run_signing()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_fallback_cleanup_is_idempotent(self):
        private = self.runner / "wallpaper-signing"
        private.mkdir()
        (private / "signing.keychain-db").touch()
        (private / "certificate.p12").write_bytes(b"private fixture")
        for _ in range(2):
            subprocess.run(["bash", str(SCRIPT), "cleanup"], cwd=ROOT, env=self.env, check=True)
        self.assertFalse(private.exists())


if __name__ == "__main__":
    unittest.main()
