from __future__ import annotations

import re
from collections import Counter

from .config import QualityConfig

EMAIL = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)
PHONE = re.compile(r"(?<!\d)(?:\+?\d[\d\s().-]{7,}\d)(?!\d)")
WINDOWS_PATH = re.compile(r"\b[A-Za-z]:\\(?:[^\\\r\n]+\\)*[^\\\r\n]*")
UNIX_HOME = re.compile(r"(?<!\w)/(?:home|Users)/[^/\s]+(?:/[^\s]*)?")


def evidence_is_exact(evidence: list[str], source: str) -> bool:
    return bool(evidence) and all(item.strip() and item in source for item in evidence)


def output_policy_violations(text: str, config: QualityConfig) -> list[str]:
    violations: list[str] = []
    if len(text) > config.maximum_answer_characters:
        violations.append("answer_too_long")
    if config.reject_if_personal_data and (EMAIL.search(text) or PHONE.search(text)):
        violations.append("possible_personal_data")
    if config.reject_absolute_local_paths and (WINDOWS_PATH.search(text) or UNIX_HOME.search(text)):
        violations.append("absolute_local_path")
    return violations


def _tokens(text: str) -> list[str]:
    return re.findall(r"[a-z0-9_$]+", text.lower())


def _shingles(text: str, width: int = 4) -> Counter[tuple[str, ...]]:
    tokens = _tokens(text)
    if len(tokens) < width:
        return Counter({tuple(tokens): 1}) if tokens else Counter()
    return Counter(tuple(tokens[index : index + width]) for index in range(len(tokens) - width + 1))


def multiset_jaccard(left: str, right: str) -> float:
    a = _shingles(left)
    b = _shingles(right)
    if not a and not b:
        return 1.0
    intersection = sum((a & b).values())
    union = sum((a | b).values())
    return intersection / union if union else 0.0
