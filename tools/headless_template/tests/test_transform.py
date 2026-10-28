from pathlib import Path
import tempfile
import unittest
from unittest import mock

from headless_template.transform import IDENTITIES, REMOVED_SECTIONS, TransformError, transform_template
from headless_template.writer import SafeWriteFailure, ValidationFailure, write_validated


def source_template() -> str:
    node_sections = "\n".join(
        f"{'[' * depth}{name}{']' * depth}\nvalue = keep-out\n"
        for depth, name in REMOVED_SECTIONS
        if depth == 2
    )
    parameter_sections = "\n".join(
        f"{'[' * depth}{name}{']' * depth}\nvalue = keep-out\n"
        for depth, name in REMOVED_SECTIONS
        if depth == 3
    )
    return (
        "[cluster demo]\n"
        "[[node defaults]]\n"
        "[[[configuration]]]\n"
        "existing.value = preserved\n"
        f"{node_sections}"
        "[parameters]\n"
        f"{parameter_sections}"
        "[[nodearray compute]]\n"
        "[[[cluster-init cyclecloud/slurm:default]]]\n"
        "[[[cluster-init cyclecloud/slurm:execute]]]\n"
        "[[[configuration]]]\n"
        "keep = yes\n"
    )


class TransformTests(unittest.TestCase):
    def test_clean_source_transformation(self) -> None:
        result = transform_template(source_template())
        for key, value in IDENTITIES.items():
            self.assertIn(f"{key} = {value}", result.content)
        for _, name in REMOVED_SECTIONS:
            self.assertNotIn(name, result.content)
        self.assertIn("existing.value = preserved", result.content)
        self.assertIn("nodearray compute", result.content)
        self.assertIn("cyclecloud/slurm:default:4.0.9", result.content)
        self.assertIn("cyclecloud/slurm:execute:4.0.9", result.content)

    def test_already_transformed_source(self) -> None:
        first = transform_template(source_template())
        second = transform_template(first.content)
        self.assertEqual(first.content, second.content)
        self.assertEqual((), second.removed_sections)

    def test_conflicting_identity_fails(self) -> None:
        source = source_template().replace(
            "existing.value = preserved\n", "slurm.user.uid = 42\n"
        )
        with self.assertRaisesRegex(TransformError, "Conflicting"):
            transform_template(source)

    def test_matching_identity_is_preserved(self) -> None:
        properties = "".join(f"{key} = {value}\n" for key, value in IDENTITIES.items())
        source = source_template().replace("existing.value = preserved\n", properties)
        self.assertIn(properties, transform_template(source).content)

    def test_each_missing_section_fails_closed(self) -> None:
        for depth, name in REMOVED_SECTIONS:
            header = f"{'[' * depth}{name}{']' * depth}\nvalue = keep-out\n"
            with self.subTest(name=name), self.assertRaisesRegex(TransformError, "missing"):
                transform_template(source_template().replace(header, ""))

    def test_duplicate_and_malformed_headers_fail(self) -> None:
        duplicate = source_template() + "[[node scheduler]]\n"
        with self.assertRaisesRegex(TransformError, "Duplicate"):
            transform_template(duplicate)
        with self.assertRaisesRegex(TransformError, "Malformed"):
            transform_template(source_template().replace("[[node defaults]]", "[[node defaults]"))

    def test_validator_rejection_preserves_destination(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            destination = root / "destination"
            source.write_text(source_template())
            destination.write_text("last-valid")
            with self.assertRaises(ValidationFailure):
                write_validated(
                    source=source,
                    destination=destination,
                    candidate="candidate",
                    validator="/bin/false",
                )
            self.assertEqual("last-valid", destination.read_text())
            self.assertEqual([], list(root.glob(".*.tmp")))

    def test_repeated_equal_content_is_noop(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            destination = root / "destination"
            source.write_text("source")
            destination.write_text("candidate")
            result = write_validated(
                source=source,
                destination=destination,
                candidate="candidate",
                validator="/bin/false",
            )
            self.assertFalse(result.changed)
            self.assertEqual(64, len(result.destination_digest))

    def test_destination_write_failure_is_explicit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.write_text("source")
            with mock.patch("tempfile.mkstemp", side_effect=PermissionError("denied")):
                with self.assertRaises(SafeWriteFailure):
                    write_validated(
                        source=source,
                        destination=root / "destination",
                        candidate="candidate",
                        validator="/bin/true",
                    )

    def test_interrupted_replace_preserves_destination_and_cleans_temp(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            destination = root / "destination"
            source.write_text("source")
            destination.write_text("last-valid")
            with mock.patch("os.replace", side_effect=OSError("interrupted")):
                with self.assertRaises(SafeWriteFailure):
                    write_validated(
                        source=source,
                        destination=destination,
                        candidate="candidate",
                        validator="/bin/true",
                    )
            self.assertEqual("last-valid", destination.read_text())
            self.assertEqual([], list(root.glob(".*.tmp")))


if __name__ == "__main__":
    unittest.main()
