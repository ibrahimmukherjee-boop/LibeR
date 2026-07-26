from __future__ import annotations

from datetime import UTC, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


def utc_now() -> str:
    return datetime.now(UTC).isoformat()


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class SourceDefinition(StrictModel):
    id: str
    path: str
    license: str
    rights_basis: Literal["owned", "licensed", "public_domain", "permission"]
    redistributable: bool
    description: str = ""
    include: list[str] = Field(default_factory=lambda: ["**/*"])
    exclude: list[str] = Field(default_factory=list)


class SourceManifest(StrictModel):
    sources: list[SourceDefinition]

    @field_validator("sources")
    @classmethod
    def unique_ids(cls, value: list[SourceDefinition]) -> list[SourceDefinition]:
        ids = [source.id for source in value]
        if len(ids) != len(set(ids)):
            raise ValueError("Source IDs must be unique")
        return value


class DocumentRecord(StrictModel):
    document_id: str
    source_id: str
    relative_path: str
    source_sha256: str
    license: str
    rights_basis: str
    redistributable: bool
    characters: int


class ChunkRecord(StrictModel):
    chunk_id: str
    document_id: str
    source_id: str
    relative_path: str
    source_sha256: str
    chunk_sha256: str
    ordinal: int
    start_character: int
    end_character: int
    text: str
    license: str
    rights_basis: str
    redistributable: bool


class QuestionProposal(StrictModel):
    question: str = Field(min_length=12, max_length=1000)
    category: str = Field(min_length=2, max_length=80)
    difficulty: Literal["basic", "intermediate", "advanced"]
    evidence: list[str] = Field(min_length=1, max_length=5)


class ProposalBatch(StrictModel):
    proposals: list[QuestionProposal] = Field(min_length=1, max_length=12)


class GroundedAnswer(StrictModel):
    answer: str = Field(min_length=10, max_length=12000)
    evidence: list[str] = Field(min_length=1, max_length=8)
    groundedness: float = Field(ge=0, le=1)
    confidence: float = Field(ge=0, le=1)
    limitations: list[str] = Field(default_factory=list, max_length=8)


class Adjudication(StrictModel):
    accepted: bool
    score: float = Field(ge=0, le=1)
    groundedness: float = Field(ge=0, le=1)
    confidence: float = Field(ge=0, le=1)
    reasons: list[str] = Field(default_factory=list, max_length=12)
    corrected_answer: str = Field(min_length=0, max_length=12000)
    evidence: list[str] = Field(default_factory=list, max_length=8)


class RejectedAnswer(StrictModel):
    answer: str = Field(min_length=5, max_length=12000)
    defect: str = Field(min_length=5, max_length=1000)


class CandidateRecord(StrictModel):
    item_id: str
    chunk_id: str
    document_id: str
    source_id: str
    relative_path: str
    source_sha256: str
    chunk_sha256: str
    license: str
    rights_basis: str
    redistributable: bool
    question: str
    category: str
    difficulty: str
    answer: str
    evidence: list[str]
    groundedness: float
    confidence: float
    teacher_model: str
    teacher_options: dict
    created_at: str = Field(default_factory=utc_now)


class JudgedRecord(CandidateRecord):
    accepted: bool
    judge_score: float
    judge_groundedness: float
    judge_confidence: float
    judge_reasons: list[str]
    judge_model: str
    final_answer: str
    final_evidence: list[str]
    rejected_answer: str | None = None
    rejected_defect: str | None = None
    judged_at: str = Field(default_factory=utc_now)


class TrainingRecord(StrictModel):
    id: str
    messages: list[dict[str, str]]
    metadata: dict

    @model_validator(mode="after")
    def validate_message_roles(self) -> TrainingRecord:
        roles = [message.get("role") for message in self.messages]
        if roles != ["system", "user", "assistant"]:
            raise ValueError("Training records must contain system, user, assistant roles")
        return self


class PreferenceRecord(StrictModel):
    id: str
    prompt: list[dict[str, str]]
    chosen: list[dict[str, str]]
    rejected: list[dict[str, str]]
    metadata: dict


class EvaluationAssessment(StrictModel):
    technically_correct: bool
    grounded: bool
    useful: bool
    safe: bool
    score: float = Field(ge=0, le=1)
    reasons: list[str] = Field(default_factory=list, max_length=10)
