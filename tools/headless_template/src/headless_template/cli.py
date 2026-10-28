from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from .transform import TransformError, transform_template
from .writer import SafeWriteFailure, ValidationFailure, digest, write_validated


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="headless-template")
    commands = root.add_subparsers(dest="command", required=True)
    transform = commands.add_parser("transform")
    transform.add_argument("--source", type=Path, required=True)
    transform.add_argument("--destination", type=Path, required=True)
    transform.add_argument("--validator", required=True)
    transform.add_argument("--slurm-project-version", default="4.0.9")
    validate = commands.add_parser("validate")
    validate.add_argument("candidate", type=Path)
    validate.add_argument("--slurm-project-version", default="4.0.9")
    return root


def _safe_paths(source: Path, destination: Path) -> tuple[Path, Path]:
    source = source.resolve(strict=True)
    destination = destination.resolve(strict=False)
    if source == destination:
        raise ValueError("Source and destination must differ")
    if not destination.parent.is_dir():
        raise ValueError("Destination directory does not exist")
    return source, destination


def run(arguments: list[str] | None = None) -> int:
    try:
        namespace = parser().parse_args(arguments)
        if namespace.command == "validate":
            candidate = namespace.candidate.resolve(strict=True)
            candidate_bytes = candidate.read_bytes()
            result = transform_template(
                candidate_bytes.decode("utf-8"),
                namespace.slurm_project_version,
            )
            if result.removed_sections or result.content.encode("utf-8") != candidate_bytes:
                raise TransformError(
                    "Candidate is not an already-transformed headless template", 4
                )
            print(
                json.dumps(
                    {
                        "status": "valid",
                        "candidate_digest": digest(candidate_bytes),
                    },
                    sort_keys=True,
                )
            )
            return 0

        source, destination = _safe_paths(namespace.source, namespace.destination)
        result = transform_template(
            source.read_bytes().decode("utf-8"),
            namespace.slurm_project_version,
        )
        write_result = write_validated(
            source=source,
            destination=destination,
            candidate=result.content,
            validator=namespace.validator,
        )
        print(
            json.dumps(
                {
                    "status": "valid",
                    "source_digest": write_result.source_digest,
                    "destination_digest": write_result.destination_digest,
                    "changed": write_result.changed,
                    "removed_sections": list(result.removed_sections),
                },
                sort_keys=True,
            )
        )
        return 0
    except (argparse.ArgumentError, ValueError, FileNotFoundError) as exc:
        print(f"Invalid arguments: {exc}", file=sys.stderr)
        return 2
    except TransformError as exc:
        print(str(exc), file=sys.stderr)
        return exc.exit_code
    except ValidationFailure as exc:
        print(f"Candidate validation failed: {exc}", file=sys.stderr)
        return 5
    except SafeWriteFailure as exc:
        print(str(exc), file=sys.stderr)
        return 6


def main() -> None:
    raise SystemExit(run())


if __name__ == "__main__":
    main()
