import ast
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from headless_template.cli import run

from test_transform import source_template


class ContractTests(unittest.TestCase):
    def test_success_output_and_noop(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            destination = root / "destination"
            source.write_text(source_template())
            first_output = io.StringIO()
            with contextlib.redirect_stdout(first_output):
                self.assertEqual(
                    0,
                    run(
                        [
                            "transform",
                            "--source",
                            str(source),
                            "--destination",
                            str(destination),
                            "--validator",
                            "/bin/true",
                        ]
                    ),
                )
            first = json.loads(first_output.getvalue())
            self.assertTrue(first["changed"])
            self.assertEqual(64, len(first["source_digest"]))
            self.assertEqual(13, len(first["removed_sections"]))

            second_output = io.StringIO()
            with contextlib.redirect_stdout(second_output):
                self.assertEqual(
                    0,
                    run(
                        [
                            "transform",
                            "--source",
                            str(source),
                            "--destination",
                            str(destination),
                            "--validator",
                            "/bin/true",
                        ]
                    ),
                )
            self.assertFalse(json.loads(second_output.getvalue())["changed"])

    def test_argument_and_validation_exit_codes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.write_text(source_template())
            self.assertEqual(
                2,
                run(
                    [
                        "transform",
                        "--source",
                        str(source),
                        "--destination",
                        str(source),
                        "--validator",
                        "/bin/true",
                    ]
                ),
            )
            self.assertEqual(
                5,
                run(
                    [
                        "transform",
                        "--source",
                        str(source),
                        "--destination",
                        str(root / "destination"),
                        "--validator",
                        "/bin/false",
                    ]
                ),
            )

    def test_validate_accepts_only_an_already_headless_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            destination = root / "destination"
            source.write_text(source_template())
            self.assertEqual(
                0,
                run(
                    [
                        "transform",
                        "--source",
                        str(source),
                        "--destination",
                        str(destination),
                        "--validator",
                        "/bin/true",
                    ]
                ),
            )
            self.assertEqual(0, run(["validate", str(destination)]))
            self.assertEqual(4, run(["validate", str(source)]))

    def test_package_module_exposes_cli_entry_point(self) -> None:
        package_root = Path(__file__).parents[1] / "src"
        environment = {**os.environ, "PYTHONPATH": str(package_root)}
        result = subprocess.run(
            [sys.executable, "-m", "headless_template", "--help"],
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("transform", result.stdout)
        self.assertIn("validate", result.stdout)

    def test_no_azure_or_deployment_imports(self) -> None:
        package = Path(__file__).parents[1] / "src" / "headless_template"
        prohibited = {"azure", "azurerm", "terraform", "boto3"}
        for path in package.glob("*.py"):
            tree = ast.parse(path.read_text())
            imports = {
                alias.name.split(".")[0]
                for node in ast.walk(tree)
                if isinstance(node, (ast.Import, ast.ImportFrom))
                for alias in (
                    node.names if isinstance(node, ast.Import) else [ast.alias(node.module or "")]
                )
            }
            self.assertTrue(prohibited.isdisjoint(imports), path)


if __name__ == "__main__":
    unittest.main()
