from pathlib import Path

from liber_distill.ingest import ingest_sources
from liber_distill.io import read_jsonl


def test_ingest_creates_hashed_documents_and_chunks(temp_config):
    audit = ingest_sources(temp_config)
    work = temp_config.resolve(temp_config.paths.work_dir)
    documents = list(read_jsonl(work / "documents.jsonl"))
    chunks = list(read_jsonl(work / "chunks.jsonl"))

    assert audit["documents"] == 1
    assert documents[0]["relative_path"] == "source.md"
    assert len(documents[0]["source_sha256"]) == 64
    assert chunks
    assert all(len(chunk["chunk_sha256"]) == 64 for chunk in chunks)
    assert Path(work / "ingestion_audit.json").exists()
