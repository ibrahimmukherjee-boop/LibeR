import pytest

from liber_distill.chunking import chunk_text


def test_chunking_prefers_boundaries_and_retains_ends():
    text = "First paragraph.\n\n" + ("middle sentence. " * 50) + "\n\nLast paragraph."
    chunks = chunk_text(text, size=180, overlap=25)

    assert len(chunks) > 2
    assert chunks[0][0] == 0
    assert chunks[-1][1] == len(text)
    assert chunks[0][2].startswith("First paragraph.")
    assert chunks[-1][2].endswith("Last paragraph.")
    assert all(start < end and content for start, end, content in chunks)


def test_chunking_rejects_invalid_overlap():
    with pytest.raises(ValueError):
        chunk_text("abc", size=10, overlap=10)
