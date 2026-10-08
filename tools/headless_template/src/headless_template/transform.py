from __future__ import annotations

from dataclasses import dataclass
import re

from .parser import (
    Section,
    TemplateAmbiguityError,
    TemplateSyntaxError,
    find_unique,
    parse_sections,
)


IDENTITIES = {
    "slurm.user.name": "slurm",
    "slurm.user.uid": "11100",
    "slurm.user.gid": "11100",
    "munge.user.name": "munge",
    "munge.user.uid": "11101",
    "munge.user.gid": "11101",
}

REMOVED_SECTIONS = (
    (2, "node scheduler"),
    (2, "nodearray scheduler-ha"),
    (2, "nodearray login"),
    (3, "parameter SchedulerMachineType"),
    (3, "parameter loginMachineType"),
    (3, "parameter NumberLoginNodes"),
    (3, "parameter SchedulerHostName"),
    (3, "parameter SchedulerImageName"),
    (3, "parameter LoginImageName"),
    (3, "parameter SchedulerClusterInitSpecs"),
    (3, "parameter LoginClusterInitSpecs"),
    (3, "parameter SchedulerZone"),
    (3, "parameter SchedulerHAZone"),
)

ASSIGNMENT = re.compile(
    r"^(?P<indent>[ \t]*)(?P<key>[A-Za-z0-9_.-]+)[ \t]*=[ \t]*(?P<value>.*?)[ \t]*(?:\r?\n)?$"
)


class TransformError(Exception):
    def __init__(self, message: str, exit_code: int) -> None:
        super().__init__(message)
        self.exit_code = exit_code


@dataclass(frozen=True)
class TransformResult:
    content: str
    removed_sections: tuple[str, ...]


def _target_sections(sections: list[Section]) -> tuple[list[Section], bool]:
    found: list[Section] = []
    missing = 0
    for depth, name in REMOVED_SECTIONS:
        matches = [
            section for section in sections if section.depth == depth and section.name == name
        ]
        if len(matches) > 1:
            raise TransformError(f"Duplicate removable section: {name}", 4)
        if matches:
            found.append(matches[0])
        else:
            missing += 1
    return found, missing == len(REMOVED_SECTIONS)


def _apply_identities(lines: list[str], configuration: Section) -> bool:
    assignments: dict[str, tuple[int, str]] = {}
    for index in range(configuration.start + 1, configuration.end):
        match = ASSIGNMENT.fullmatch(lines[index])
        if match is None or match["key"] not in IDENTITIES:
            continue
        key = match["key"]
        if key in assignments:
            raise TransformError(f"Duplicate identity property: {key}", 4)
        assignments[key] = (index, match["value"])

    for key, (_, actual) in assignments.items():
        if actual != IDENTITIES[key]:
            raise TransformError(f"Conflicting identity property: {key}", 4)

    missing = [key for key in IDENTITIES if key not in assignments]
    if not missing:
        return False

    newline = "\r\n" if lines[configuration.start].endswith("\r\n") else "\n"
    insertion = [f"{key} = {IDENTITIES[key]}{newline}" for key in missing]
    lines[configuration.end:configuration.end] = insertion
    return True


def transform_template(source: str) -> TransformResult:
    lines = source.splitlines(keepends=True)
    try:
        sections = parse_sections(lines)
        defaults = find_unique(sections, "node defaults", 2)
        configurations = [
            section
            for section in sections
            if section.name == "configuration"
            and section.depth == 3
            and defaults.start < section.start < defaults.end
        ]
        if len(configurations) != 1:
            raise TemplateAmbiguityError(
                f"Expected one configuration under node defaults; found {len(configurations)}"
            )
    except TemplateSyntaxError as exc:
        raise TransformError(str(exc), 3) from exc
    except TemplateAmbiguityError as exc:
        raise TransformError(str(exc), 4) from exc

    targets, already_headless = _target_sections(sections)
    if not already_headless and len(targets) != len(REMOVED_SECTIONS):
        raise TransformError("One or more removable sections are missing", 4)

    if targets:
        for section in sorted(targets, key=lambda item: item.start, reverse=True):
            del lines[section.start : section.end]

    try:
        updated_sections = parse_sections(lines)
        updated_defaults = find_unique(updated_sections, "node defaults", 2)
        updated_configurations = [
            section
            for section in updated_sections
            if section.name == "configuration"
            and section.depth == 3
            and updated_defaults.start < section.start < updated_defaults.end
        ]
        if len(updated_configurations) != 1:
            raise TemplateAmbiguityError(
                f"Expected one configuration under node defaults; found {len(updated_configurations)}"
            )
    except (TemplateSyntaxError, TemplateAmbiguityError) as exc:
        raise TransformError(str(exc), 4) from exc

    identity_changed = _apply_identities(lines, updated_configurations[0])
    if already_headless and identity_changed:
        raise TransformError(
            "Template is partially transformed: removable sections are absent but identities were incomplete",
            4,
        )

    return TransformResult(
        content="".join(lines),
        removed_sections=tuple(name for _, name in REMOVED_SECTIONS) if targets else (),
    )
