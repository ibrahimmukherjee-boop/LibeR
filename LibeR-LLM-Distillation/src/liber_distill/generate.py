from __future__ import annotations

import json
from pathlib import Path

from rich.console import Console
from rich.progress import Progress

from .config import DistillConfig
from .io import append_jsonl, read_jsonl, sha256_text
from .ollama import OllamaClient
from .quality import evidence_is_exact, output_policy_violations
from .schemas import (
    Adjudication,
    CandidateRecord,
    ChunkRecord,
    GroundedAnswer,
    JudgedRecord,
    ProposalBatch,
    RejectedAnswer,
)


def _prompt(config: DistillConfig, name: str) -> str:
    return (config.project_root / "prompts" / name).read_text(encoding="utf-8")


def _options(config: DistillConfig, temperature: float) -> dict:
    return {
        "temperature": temperature,
        "num_ctx": config.generation.num_ctx,
        "num_predict": config.generation.num_predict,
        "seed": config.generation.seed,
    }


def _completed_ids(path: Path, key: str) -> set[str]:
    return {str(row[key]) for row in read_jsonl(path) if row.get("status") == "completed"}


def generate_candidates(
    config: DistillConfig, console: Console | None = None, limit: int | None = None
) -> dict:
    console = console or Console()
    work_dir = config.resolve(config.paths.work_dir)
    chunks = [ChunkRecord.model_validate(row) for row in read_jsonl(work_dir / "chunks.jsonl")]
    if limit is not None:
        chunks = chunks[:limit]
    if not chunks:
        raise RuntimeError("No chunks found. Run `liber-distill ingest` first.")

    client = OllamaClient(
        config.generation.base_url,
        config.generation.request_timeout_seconds,
        config.generation.max_retries,
    )
    state_path = work_dir / "generation_state.jsonl"
    errors_path = work_dir / "generation_errors.jsonl"
    candidates_path = work_dir / "candidates.jsonl"
    done = _completed_ids(state_path, "chunk_id") if config.generation.resume else set()
    existing = {row["item_id"] for row in read_jsonl(candidates_path)}
    generated = 0
    skipped = 0
    failed = 0

    propose_system = _prompt(config, "propose_questions.md")
    answer_system = _prompt(config, "answer_grounded.md")
    options = _options(config, config.generation.temperature)

    with Progress(console=console) as progress:
        task = progress.add_task("Generating grounded examples", total=len(chunks))
        for chunk in chunks:
            if chunk.chunk_id in done:
                skipped += 1
                progress.advance(task)
                continue
            try:
                proposal_user = (
                    f"Allowed categories: {json.dumps(config.generation.categories)}\n"
                    f"Return exactly {config.generation.questions_per_chunk} proposals.\n\n"
                    f"<SOURCE id={chunk.chunk_id}>\n{chunk.text}\n</SOURCE>"
                )
                batch = client.chat_json(
                    model=config.generation.teacher_model,
                    system=propose_system,
                    user=proposal_user,
                    response_type=ProposalBatch,
                    options=options,
                    think=config.generation.think,
                )
                valid_count = 0
                for proposal in batch.proposals[: config.generation.questions_per_chunk]:
                    if proposal.category not in config.generation.categories:
                        append_jsonl(
                            errors_path,
                            {
                                "chunk_id": chunk.chunk_id,
                                "stage": "proposal",
                                "reason": "unknown_category",
                                "category": proposal.category,
                            },
                        )
                        continue
                    if not evidence_is_exact(proposal.evidence, chunk.text):
                        append_jsonl(
                            errors_path,
                            {
                                "chunk_id": chunk.chunk_id,
                                "stage": "proposal",
                                "reason": "non_exact_evidence",
                                "question": proposal.question,
                            },
                        )
                        continue
                    item_id = sha256_text(f"{chunk.chunk_id}\0{proposal.question.strip().lower()}")[
                        :28
                    ]
                    if item_id in existing:
                        valid_count += 1
                        continue
                    answer_user = (
                        f"Question: {proposal.question}\n"
                        "Proposed evidence: "
                        f"{json.dumps(proposal.evidence, ensure_ascii=False)}\n\n"
                        f"<SOURCE id={chunk.chunk_id}>\n{chunk.text}\n</SOURCE>"
                    )
                    answer = client.chat_json(
                        model=config.generation.teacher_model,
                        system=answer_system,
                        user=answer_user,
                        response_type=GroundedAnswer,
                        options=options,
                        think=config.generation.think,
                    )
                    violations = output_policy_violations(answer.answer, config.quality)
                    if config.quality.require_exact_evidence and not evidence_is_exact(
                        answer.evidence, chunk.text
                    ):
                        violations.append("non_exact_answer_evidence")
                    if violations:
                        append_jsonl(
                            errors_path,
                            {
                                "chunk_id": chunk.chunk_id,
                                "item_id": item_id,
                                "stage": "answer",
                                "reason": violations,
                            },
                        )
                        continue
                    record = CandidateRecord(
                        item_id=item_id,
                        chunk_id=chunk.chunk_id,
                        document_id=chunk.document_id,
                        source_id=chunk.source_id,
                        relative_path=chunk.relative_path,
                        source_sha256=chunk.source_sha256,
                        chunk_sha256=chunk.chunk_sha256,
                        license=chunk.license,
                        rights_basis=chunk.rights_basis,
                        redistributable=chunk.redistributable,
                        question=proposal.question.strip(),
                        category=proposal.category,
                        difficulty=proposal.difficulty,
                        answer=answer.answer.strip(),
                        evidence=answer.evidence,
                        groundedness=answer.groundedness,
                        confidence=answer.confidence,
                        teacher_model=config.generation.teacher_model,
                        teacher_options={**options, "think": config.generation.think},
                    )
                    append_jsonl(candidates_path, record.model_dump())
                    existing.add(item_id)
                    generated += 1
                    valid_count += 1
                append_jsonl(
                    state_path,
                    {
                        "chunk_id": chunk.chunk_id,
                        "status": "completed",
                        "valid_candidates": valid_count,
                    },
                )
            except Exception as exc:
                failed += 1
                append_jsonl(
                    errors_path,
                    {
                        "chunk_id": chunk.chunk_id,
                        "stage": "generation",
                        "reason": type(exc).__name__,
                        "message": str(exc),
                    },
                )
                console.print(f"[red]{chunk.chunk_id}: {exc}[/red]")
            progress.advance(task)

    summary = {
        "chunks": len(chunks),
        "generated": generated,
        "skipped_completed_chunks": skipped,
        "failed_chunks": failed,
        "candidates": str(candidates_path),
    }
    console.print(f"[green]Generation complete:[/green] {summary}")
    return summary


def adjudicate_candidates(
    config: DistillConfig,
    console: Console | None = None,
    limit: int | None = None,
    force: bool = False,
) -> dict:
    console = console or Console()
    work_dir = config.resolve(config.paths.work_dir)
    chunk_map = {
        row["chunk_id"]: ChunkRecord.model_validate(row)
        for row in read_jsonl(work_dir / "chunks.jsonl")
    }
    candidates = [
        CandidateRecord.model_validate(row) for row in read_jsonl(work_dir / "candidates.jsonl")
    ]
    if limit is not None:
        candidates = candidates[:limit]
    if not candidates:
        raise RuntimeError("No candidates found. Run `liber-distill generate` first.")

    judged_path = work_dir / "judged.jsonl"
    errors_path = work_dir / "adjudication_errors.jsonl"
    existing = {row["item_id"] for row in read_jsonl(judged_path)}
    client = OllamaClient(
        config.generation.base_url,
        config.generation.request_timeout_seconds,
        config.generation.max_retries,
    )
    judge_system = _prompt(config, "adjudicate.md")
    reject_system = _prompt(config, "make_rejected_answer.md")
    judge_options = _options(config, config.generation.judge_temperature)
    reviewed = accepted_count = skipped = failed = 0

    with Progress(console=console) as progress:
        task = progress.add_task("Adjudicating examples", total=len(candidates))
        for candidate in candidates:
            if config.generation.resume and not force and candidate.item_id in existing:
                skipped += 1
                progress.advance(task)
                continue
            chunk = chunk_map.get(candidate.chunk_id)
            if chunk is None:
                append_jsonl(
                    errors_path,
                    {
                        "item_id": candidate.item_id,
                        "reason": "source_chunk_missing",
                    },
                )
                failed += 1
                progress.advance(task)
                continue
            try:
                judge_user = (
                    f"Question: {candidate.question}\n\n"
                    f"Proposed answer: {candidate.answer}\n\n"
                    f"Claimed evidence: {json.dumps(candidate.evidence, ensure_ascii=False)}\n\n"
                    f"<SOURCE id={chunk.chunk_id}>\n{chunk.text}\n</SOURCE>"
                )
                decision = client.chat_json(
                    model=config.generation.judge_model,
                    system=judge_system,
                    user=judge_user,
                    response_type=Adjudication,
                    options=judge_options,
                    think=config.generation.think,
                )
                final_answer = (decision.corrected_answer or candidate.answer).strip()
                adjudication_notes: list[str] = []
                final_evidence = decision.evidence or candidate.evidence
                if not evidence_is_exact(final_evidence, chunk.text) and evidence_is_exact(
                    candidate.evidence, chunk.text
                ):
                    final_evidence = candidate.evidence
                    adjudication_notes.append(
                        "judge_evidence_replaced_with_exact_candidate_evidence"
                    )
                violations = output_policy_violations(final_answer, config.quality)
                if config.quality.require_exact_evidence and not evidence_is_exact(
                    final_evidence, chunk.text
                ):
                    violations.append("non_exact_final_evidence")
                accepted = (
                    decision.accepted
                    and decision.score >= config.quality.minimum_judge_score
                    and decision.groundedness >= config.quality.minimum_groundedness
                    and candidate.groundedness >= config.quality.minimum_groundedness
                    and not violations
                )
                rejected_answer = None
                rejected_defect = None
                if accepted and config.preference_training.enabled:
                    rejection = client.chat_json(
                        model=config.generation.judge_model,
                        system=reject_system,
                        user=(
                            f"Question: {candidate.question}\n\n"
                            f"Accepted answer: {final_answer}\n\n"
                            f"<SOURCE id={chunk.chunk_id}>\n{chunk.text}\n</SOURCE>"
                        ),
                        response_type=RejectedAnswer,
                        options=judge_options,
                        think=config.generation.think,
                    )
                    rejected_answer = rejection.answer.strip()
                    rejected_defect = rejection.defect.strip()
                    reject_violations = output_policy_violations(rejected_answer, config.quality)
                    if reject_violations:
                        rejected_answer = None
                        rejected_defect = None
                record = JudgedRecord(
                    **candidate.model_dump(),
                    accepted=accepted,
                    judge_score=decision.score,
                    judge_groundedness=decision.groundedness,
                    judge_confidence=decision.confidence,
                    judge_reasons=decision.reasons + adjudication_notes + violations,
                    judge_model=config.generation.judge_model,
                    final_answer=final_answer,
                    final_evidence=final_evidence,
                    rejected_answer=rejected_answer,
                    rejected_defect=rejected_defect,
                )
                append_jsonl(judged_path, record.model_dump())
                existing.add(candidate.item_id)
                reviewed += 1
                accepted_count += int(accepted)
            except Exception as exc:
                failed += 1
                append_jsonl(
                    errors_path,
                    {
                        "item_id": candidate.item_id,
                        "reason": type(exc).__name__,
                        "message": str(exc),
                    },
                )
                console.print(f"[red]{candidate.item_id}: {exc}[/red]")
            progress.advance(task)

    summary = {
        "candidates": len(candidates),
        "reviewed": reviewed,
        "accepted": accepted_count,
        "skipped": skipped,
        "failed": failed,
        "judged": str(judged_path),
    }
    console.print(f"[green]Adjudication complete:[/green] {summary}")
    return summary
