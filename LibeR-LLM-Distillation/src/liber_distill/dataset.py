from __future__ import annotations

import hashlib
import json
from collections import Counter, defaultdict

from rich.console import Console

from .config import DistillConfig
from .io import (
    read_jsonl,
    sha256_file,
    sha256_text,
    write_json_atomic,
    write_jsonl_atomic,
)
from .quality import evidence_is_exact, multiset_jaccard, output_policy_violations
from .schemas import (
    ChunkRecord,
    JudgedRecord,
    PreferenceRecord,
    TrainingRecord,
)


def _stable_order(value: str, seed: int) -> str:
    return hashlib.sha256(f"{seed}\0{value}".encode()).hexdigest()


def _group_key(record: JudgedRecord, group_by: str) -> str:
    return record.document_id if group_by == "document" else record.source_id


def _group_splits(records: list[JudgedRecord], config: DistillConfig) -> dict[str, str]:
    groups = sorted(
        {_group_key(record, config.split.group_by) for record in records},
        key=lambda value: _stable_order(value, config.project.seed),
    )
    count = len(groups)
    if count == 0:
        return {}
    if count == 1:
        return {groups[0]: "train"}

    validation_count = max(1, round(count * config.split.validation_fraction)) if count >= 3 else 0
    test_count = max(1, round(count * config.split.test_fraction))
    while validation_count + test_count >= count:
        if validation_count > 0:
            validation_count -= 1
        elif test_count > 1:
            test_count -= 1
        else:
            break
    train_count = count - validation_count - test_count
    mapping: dict[str, str] = {}
    for index, group in enumerate(groups):
        if index < train_count:
            mapping[group] = "train"
        elif index < train_count + validation_count:
            mapping[group] = "validation"
        else:
            mapping[group] = "test"
    return mapping


def _deduplicate(
    records: list[JudgedRecord], threshold: float
) -> tuple[list[JudgedRecord], list[dict]]:
    kept: list[JudgedRecord] = []
    removed: list[dict] = []
    for record in sorted(records, key=lambda item: (-item.judge_score, item.item_id)):
        content = f"{record.question}\n{record.final_answer}"
        duplicate = None
        similarity = 0.0
        for prior in kept:
            if prior.category != record.category:
                continue
            value = multiset_jaccard(content, f"{prior.question}\n{prior.final_answer}")
            if value >= threshold:
                duplicate = prior.item_id
                similarity = value
                break
        if duplicate:
            removed.append(
                {
                    "item_id": record.item_id,
                    "duplicate_of": duplicate,
                    "similarity": similarity,
                }
            )
        else:
            kept.append(record)
    return kept, removed


def build_datasets(config: DistillConfig, console: Console | None = None) -> dict:
    console = console or Console()
    work_dir = config.resolve(config.paths.work_dir)
    dataset_dir = config.resolve(config.paths.dataset_dir)
    chunk_map = {
        row["chunk_id"]: ChunkRecord.model_validate(row)
        for row in read_jsonl(work_dir / "chunks.jsonl")
    }
    # Decisions are append-only. A forced re-review supersedes an earlier
    # decision without destroying the original audit record.
    reviewed_by_id = {
        row["item_id"]: JudgedRecord.model_validate(row)
        for row in read_jsonl(work_dir / "judged.jsonl")
    }
    reviewed = list(reviewed_by_id.values())
    accepted: list[JudgedRecord] = []
    excluded: list[dict] = []
    for record in reviewed:
        reasons: list[str] = []
        chunk = chunk_map.get(record.chunk_id)
        if not record.accepted:
            reasons.append("judge_rejected")
        if chunk is None:
            reasons.append("source_chunk_missing")
        elif config.quality.require_exact_evidence and not evidence_is_exact(
            record.final_evidence, chunk.text
        ):
            reasons.append("non_exact_evidence")
        reasons.extend(output_policy_violations(record.final_answer, config.quality))
        if reasons:
            excluded.append({"item_id": record.item_id, "reasons": sorted(set(reasons))})
        else:
            accepted.append(record)

    accepted, duplicates = _deduplicate(accepted, config.quality.near_duplicate_similarity)
    split_map = _group_splits(accepted, config)
    training: dict[str, list[TrainingRecord]] = defaultdict(list)
    preferences: dict[str, list[PreferenceRecord]] = defaultdict(list)
    source_licenses: Counter[str] = Counter()

    for record in accepted:
        split = split_map[_group_key(record, config.split.group_by)]
        metadata = {
            "source_id": record.source_id,
            "document_id": record.document_id,
            "relative_path": record.relative_path,
            "source_sha256": record.source_sha256,
            "chunk_sha256": record.chunk_sha256,
            "category": record.category,
            "difficulty": record.difficulty,
            "license": record.license,
            "rights_basis": record.rights_basis,
            "redistributable": record.redistributable,
            "teacher_model": record.teacher_model,
            "judge_model": record.judge_model,
            "judge_score": record.judge_score,
            "evidence": record.final_evidence,
            "split_group": _group_key(record, config.split.group_by),
        }
        training[split].append(
            TrainingRecord(
                id=record.item_id,
                messages=[
                    {"role": "system", "content": config.project.system_prompt},
                    {"role": "user", "content": record.question},
                    {"role": "assistant", "content": record.final_answer},
                ],
                metadata=metadata,
            )
        )
        if record.rejected_answer:
            preferences[split].append(
                PreferenceRecord(
                    id=record.item_id,
                    prompt=[
                        {"role": "system", "content": config.project.system_prompt},
                        {"role": "user", "content": record.question},
                    ],
                    chosen=[{"role": "assistant", "content": record.final_answer}],
                    rejected=[{"role": "assistant", "content": record.rejected_answer}],
                    metadata={**metadata, "rejected_defect": record.rejected_defect},
                )
            )
        source_licenses[record.license] += 1

    dataset_dir.mkdir(parents=True, exist_ok=True)
    all_records: list[TrainingRecord] = []
    for split in ("train", "validation", "test"):
        rows = sorted(training[split], key=lambda item: item.id)
        all_records.extend(rows)
        write_jsonl_atomic(dataset_dir / f"{split}.jsonl", (row.model_dump() for row in rows))
        pref_rows = sorted(preferences[split], key=lambda item: item.id)
        write_jsonl_atomic(
            dataset_dir / f"{split}_preferences.jsonl",
            (row.model_dump() for row in pref_rows),
        )
    write_jsonl_atomic(
        dataset_dir / "all.jsonl",
        (row.model_dump() for row in sorted(all_records, key=lambda item: item.id)),
    )
    write_jsonl_atomic(dataset_dir / "excluded.jsonl", excluded)
    write_jsonl_atomic(dataset_dir / "duplicates.jsonl", duplicates)

    audit = {
        "reviewed": len(reviewed),
        "accepted_before_deduplication": len(accepted) + len(duplicates),
        "accepted_after_deduplication": len(accepted),
        "excluded": len(excluded),
        "duplicates": len(duplicates),
        "splits": {key: len(training[key]) for key in ("train", "validation", "test")},
        "preference_splits": {
            key: len(preferences[key]) for key in ("train", "validation", "test")
        },
        "split_groups": Counter(split_map.values()),
        "licenses": dict(source_licenses),
        "contains_nonredistributable_examples": any(
            not record.redistributable for record in accepted
        ),
        "teacher_model": config.generation.teacher_model,
        "judge_model": config.generation.judge_model,
        "student_model": config.training.student_model,
    }
    audit["split_groups"] = dict(audit["split_groups"])
    write_json_atomic(dataset_dir / "dataset_audit.json", audit)
    dataset_files = [
        dataset_dir / name
        for name in (
            "train.jsonl",
            "validation.jsonl",
            "test.jsonl",
            "train_preferences.jsonl",
            "validation_preferences.jsonl",
            "test_preferences.jsonl",
            "dataset_audit.json",
        )
    ]
    manifest_path = config.resolve(config.paths.source_manifest)
    reproducibility = {
        "config_sha256": sha256_text(json.dumps(config.model_dump(mode="json"), sort_keys=True)),
        "source_manifest_sha256": sha256_file(manifest_path),
        "prompt_sha256": {
            path.name: sha256_file(path)
            for path in sorted((config.project_root / "prompts").glob("*.md"))
        },
        "dataset_sha256": {path.name: sha256_file(path) for path in dataset_files if path.exists()},
    }
    write_json_atomic(dataset_dir / "reproducibility_manifest.json", reproducibility)
    card = (
        f"# {config.project.name} dataset\n\n"
        f"- Accepted examples: {len(accepted)}\n"
        f"- Train/validation/test: "
        f"{len(training['train'])}/{len(training['validation'])}/{len(training['test'])}\n"
        f"- Teacher: `{config.generation.teacher_model}`\n"
        f"- Judge: `{config.generation.judge_model}`\n"
        f"- Student target: `{config.training.student_model}`\n"
        f"- Split grouping: `{config.split.group_by}`\n"
        f"- Source licences: {dict(source_licenses)}\n"
        f"- Contains non-redistributable rows: "
        f"{audit['contains_nonredistributable_examples']}\n\n"
        "See `dataset_audit.json` and `reproducibility_manifest.json` for the "
        "machine-readable record. This synthetic dataset is for research and "
        "teaching; it does not authorise autonomous clinical advice.\n"
    )
    (dataset_dir / "DATASET_CARD.md").write_text(card, encoding="utf-8")
    console.print(f"[green]Dataset complete:[/green] {audit}")
    return audit
