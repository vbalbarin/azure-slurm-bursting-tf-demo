from __future__ import annotations

from dataclasses import dataclass
import re


HEADER = re.compile(r"^(?P<open>\[+)(?P<body>[^\[\]]+)(?P<close>\]+)[ \t]*(?:\r?\n)?$")


class TemplateSyntaxError(ValueError):
    """The template cannot be parsed safely."""


class TemplateAmbiguityError(ValueError):
    """The requested transformation is ambiguous or conflicts with existing state."""


@dataclass(frozen=True)
class Section:
    name: str
    depth: int
    start: int
    end: int


def parse_sections(lines: list[str]) -> list[Section]:
    headers: list[tuple[str, int, int]] = []
    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if not stripped.startswith("["):
            continue
        match = HEADER.fullmatch(stripped)
        if match is None or len(match["open"]) != len(match["close"]):
            raise TemplateSyntaxError(f"Malformed section header at line {index + 1}")
        name = " ".join(match["body"].strip().split())
        if not name:
            raise TemplateSyntaxError(f"Empty section header at line {index + 1}")
        headers.append((name, len(match["open"]), index))

    if not headers:
        raise TemplateSyntaxError("Template contains no section headers")

    sections: list[Section] = []
    for position, (name, depth, start) in enumerate(headers):
        end = len(lines)
        for _, next_depth, next_start in headers[position + 1 :]:
            if next_depth <= depth:
                end = next_start
                break
        sections.append(Section(name=name, depth=depth, start=start, end=end))
    return sections


def find_unique(sections: list[Section], name: str, depth: int) -> Section:
    matches = [section for section in sections if section.name == name and section.depth == depth]
    if len(matches) != 1:
        raise TemplateAmbiguityError(
            f"Expected exactly one [{depth}:{name}] section; found {len(matches)}"
        )
    return matches[0]
