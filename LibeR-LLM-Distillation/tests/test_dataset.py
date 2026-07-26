from liber_distill.dataset import build_datasets
from liber_distill.io import read_jsonl, write_jsonl_atomic
from liber_distill.schemas import ChunkRecord, JudgedRecord


def _rows():
    chunks = []
    judged = []
    for index in range(6):
        text = (
            f"Document {index} explains parameter {index}. "
            f"The supported instruction is use value {index} in this example."
        )
        chunk = ChunkRecord(
            chunk_id=f"chunk-{index}",
            document_id=f"document-{index}",
            source_id="fixture",
            relative_path=f"doc-{index}.md",
            source_sha256=f"{index:064x}",
            chunk_sha256=f"{index + 10:064x}",
            ordinal=0,
            start_character=0,
            end_character=len(text),
            text=text,
            license="MIT",
            rights_basis="owned",
            redistributable=True,
        )
        evidence = [f"The supported instruction is use value {index} in this example."]
        chunks.append(chunk)
        judged.append(
            JudgedRecord(
                item_id=f"item-{index}",
                chunk_id=chunk.chunk_id,
                document_id=chunk.document_id,
                source_id=chunk.source_id,
                relative_path=chunk.relative_path,
                source_sha256=chunk.source_sha256,
                chunk_sha256=chunk.chunk_sha256,
                license="MIT",
                rights_basis="owned",
                redistributable=True,
                question=f"What does document {index} instruct the modeller to use?",
                category="model_coding",
                difficulty="basic",
                answer=f"It instructs the modeller to use value {index}.",
                evidence=evidence,
                groundedness=0.99,
                confidence=0.99,
                teacher_model="teacher",
                teacher_options={"seed": 1},
                accepted=True,
                judge_score=0.99,
                judge_groundedness=0.99,
                judge_confidence=0.99,
                judge_reasons=[],
                judge_model="judge",
                final_answer=f"Use value {index} for this documented example.",
                final_evidence=evidence,
            )
        )
    return chunks, judged


def test_dataset_splits_whole_documents(temp_config):
    work = temp_config.resolve(temp_config.paths.work_dir)
    chunks, judged = _rows()
    write_jsonl_atomic(work / "chunks.jsonl", (row.model_dump() for row in chunks))
    superseded = judged[0].model_copy(
        update={"accepted": False, "judge_reasons": ["superseded test decision"]}
    )
    write_jsonl_atomic(
        work / "judged.jsonl",
        (row.model_dump() for row in [superseded, *judged]),
    )

    audit = build_datasets(temp_config)
    dataset = temp_config.resolve(temp_config.paths.dataset_dir)
    groups = {}
    for split in ("train", "validation", "test"):
        rows = list(read_jsonl(dataset / f"{split}.jsonl"))
        for row in rows:
            document = row["metadata"]["document_id"]
            assert document not in groups
            groups[document] = split

    assert sum(audit["splits"].values()) == 6
    assert audit["reviewed"] == 6
    assert set(audit["splits"]) == {"train", "validation", "test"}
    assert all(audit["splits"][split] > 0 for split in audit["splits"])
