from __future__ import annotations

import re


def _preferred_boundary(text: str, lower: int, upper: int) -> int:
    window = text[lower:upper]
    candidates: list[int] = []
    for pattern in (r"\n\s*\n", r"\n", r"(?<=[.!?])\s+"):
        matches = list(re.finditer(pattern, window))
        if matches:
            candidates.append(lower + matches[-1].end())
    return max(candidates) if candidates else upper


def chunk_text(text: str, size: int, overlap: int) -> list[tuple[int, int, str]]:
    if size <= 0:
        raise ValueError("size must be positive")
    if overlap < 0 or overlap >= size:
        raise ValueError("overlap must satisfy 0 <= overlap < size")
    if not text.strip():
        return []

    chunks: list[tuple[int, int, str]] = []
    start = 0
    length = len(text)
    while start < length:
        proposed_end = min(start + size, length)
        end = (
            _preferred_boundary(text, start + size // 2, proposed_end)
            if proposed_end < length
            else length
        )
        if end <= start:
            end = proposed_end
        chunk = text[start:end].strip()
        if chunk:
            left_trim = len(text[start:end]) - len(text[start:end].lstrip())
            right_trim = len(text[start:end]) - len(text[start:end].rstrip())
            chunks.append((start + left_trim, end - right_trim, chunk))
        if end >= length:
            break
        next_start = max(0, end - overlap)
        if next_start <= start:
            next_start = end
        start = next_start
    return chunks
