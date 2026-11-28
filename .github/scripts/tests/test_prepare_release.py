"""Check draft/tag handling without making GitHub requests."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "prepare-release.sh"
COMMIT = "a" * 40
OTHER_COMMIT = "b" * 40
MOCK = r'''
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
with open(os.environ["RELEASE_TEST_LOG"], "a") as stream:
    stream.write(json.dumps(args) + "\n")
if Path(sys.argv[0]).name == "git":
    print(os.environ["RELEASE_TEST_HEAD"])
elif args[0] == "api":
    endpoint = next(arg for arg in args if arg.startswith("repos/"))
    if "releases?" in endpoint:
        draft = json.loads(os.environ["RELEASE_TEST_DRAFT"])
        if draft:
            draft["tag_name"] = "v1.2.3"
        print(json.dumps([[draft] if draft else []]))
    elif "matching-refs" in endpoint:
        print(json.dumps([{"ref": "refs/tags/v1.2.3"}] if os.environ["RELEASE_TEST_TAG"] == "true" else []))
    elif "commits/tags" in endpoint:
        print(os.environ["RELEASE_TEST_TAG_COMMIT"])
elif args[:2] == ["release", "create"]:
    print("https://github.com/test/repo/releases/tag/v1.2.3")
'''


class DraftTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.log = self.root / "commands.jsonl"
        mock_bin = self.root / "bin"
        mock_bin.mkdir()
        for command in ("gh", "git"):
            path = mock_bin / command
            path.write_text("#!" + sys.executable + "\n" + MOCK)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(mock_bin) + os.pathsep + os.environ["PATH"],
                        GH_REPO="test/repo", RELEASE_TAG="v1.2.3", GITHUB_SHA=COMMIT,
                        RELEASE_COMMIT=COMMIT, RUNNER_TEMP=str(self.root),
                        GITHUB_OUTPUT=str(self.root / "output"),
                        GITHUB_STEP_SUMMARY=str(self.root / "summary"),
                        GITHUB_SERVER_URL="https://github.com", RELEASE_TEST_LOG=str(self.log),
                        RELEASE_TEST_DRAFT="null", RELEASE_TEST_TAG="false",
                        RELEASE_TEST_TAG_COMMIT=COMMIT, RELEASE_TEST_HEAD=COMMIT)
        assets = self.root / "release-assets"
        assets.mkdir()
        for name in ("Game-of-Life", "City-Simulation", "System-Design"):
            (assets / (name + "-Native-Wallpaper.zip")).write_bytes(b"verified fixture")

    def run_script(self, mode):
        return subprocess.run(["bash", str(SCRIPT), mode], cwd=self.root, env=self.env,
                              capture_output=True, text=True)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_existing_tag_resolves_to_its_exact_commit(self):
        self.env.update(RELEASE_TEST_TAG="true", RELEASE_TEST_TAG_COMMIT=OTHER_COMMIT)
        result = self.run_script("resolve")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "output").read_text(), "commit=" + OTHER_COMMIT + "\n")

    def test_invalid_tags_published_releases_and_moved_tags_cannot_upload(self):
        cases = (
            {"RELEASE_TAG": "v1.2.3-unsafe"},
            {"RELEASE_TEST_DRAFT": json.dumps({"draft": False})},
            {"RELEASE_TEST_TAG": "true", "RELEASE_TEST_TAG_COMMIT": OTHER_COMMIT},
            {"RELEASE_TEST_HEAD": OTHER_COMMIT},
        )
        for case in cases:
            with self.subTest(case=case):
                original = self.env.copy()
                if self.log.exists():
                    self.log.unlink()
                self.env.update(case)
                result = self.run_script("upload")
                self.env = original
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(command[:1] == ["release"] for command in self.commands()))

    def test_creates_only_a_draft_with_current_or_historical_asset_names(self):
        for system_design in (False, True):
            with self.subTest(system_design=system_design):
                if system_design:
                    directory = self.root / "System Design"
                    directory.mkdir()
                    (directory / "Package.swift").touch()
                result = self.run_script("upload")
                self.assertEqual(result.returncode, 0, result.stderr)
                create = [command for command in self.commands() if command[:2] == ["release", "create"]][-1]
                self.assertIn("--draft", create)
                self.assertIn("--target", create)
                self.assertEqual(sum(arg.endswith(".zip") for arg in create), 3 if system_design else 2)
                self.assertIn("Developer ID signed", create[-1])

    def test_replaces_old_signing_statement_without_losing_draft_notes(self):
        self.env["RELEASE_TEST_DRAFT"] = json.dumps({"draft": True, "target_commitish": COMMIT,
            "body": "My notes.\n\nThe macOS bundles use ad-hoc signing.", "assets": [],
            "html_url": "https://github.com/test/repo/releases/tag/v1.2.3"})
        result = self.run_script("upload")
        self.assertEqual(result.returncode, 0, result.stderr)
        edit = next(command for command in self.commands() if "--notes" in command)
        self.assertTrue(edit[-1].startswith("My notes.\n\n"))
        self.assertNotIn("ad-hoc", edit[-1])


if __name__ == "__main__":
    unittest.main()
