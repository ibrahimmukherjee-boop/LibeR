from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, ConfigDict, Field, model_validator


class Section(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ProjectConfig(Section):
    name: str
    seed: int
    system_prompt: str


class PathsConfig(Section):
    source_manifest: Path
    work_dir: Path
    dataset_dir: Path
    run_dir: Path
    export_dir: Path


class IngestionConfig(Section):
    chunk_characters: int = Field(ge=300)
    overlap_characters: int = Field(ge=0)
    include_extensions: list[str]
    exclude_globs: list[str]

    @model_validator(mode="after")
    def overlap_smaller_than_chunk(self) -> IngestionConfig:
        if self.overlap_characters >= self.chunk_characters:
            raise ValueError("overlap_characters must be smaller than chunk_characters")
        return self


class GenerationConfig(Section):
    base_url: str
    teacher_model: str
    judge_model: str
    temperature: float = Field(ge=0, le=2)
    judge_temperature: float = Field(ge=0, le=2)
    num_ctx: int = Field(ge=2048)
    num_predict: int = Field(ge=128)
    think: bool
    seed: int
    questions_per_chunk: int = Field(ge=1, le=12)
    categories: list[str]
    request_timeout_seconds: float = Field(gt=0)
    max_retries: int = Field(ge=0, le=10)
    resume: bool


class QualityConfig(Section):
    minimum_judge_score: float = Field(ge=0, le=1)
    minimum_groundedness: float = Field(ge=0, le=1)
    require_exact_evidence: bool
    maximum_answer_characters: int = Field(ge=50)
    reject_if_personal_data: bool
    reject_absolute_local_paths: bool
    near_duplicate_similarity: float = Field(ge=0, le=1)


class SplitConfig(Section):
    train_fraction: float = Field(gt=0, lt=1)
    validation_fraction: float = Field(gt=0, lt=1)
    test_fraction: float = Field(gt=0, lt=1)
    group_by: str

    @model_validator(mode="after")
    def fractions_sum_to_one(self) -> SplitConfig:
        total = self.train_fraction + self.validation_fraction + self.test_fraction
        if abs(total - 1.0) > 1e-9:
            raise ValueError("Split fractions must sum to 1")
        if self.group_by not in {"document", "source"}:
            raise ValueError("split.group_by must be 'document' or 'source'")
        return self


class TrainingConfig(Section):
    student_model: str
    max_sequence_length: int = Field(ge=128)
    output_dir: Path
    load_in_4bit: bool
    bf16: bool
    fp16: bool
    epochs: float = Field(gt=0)
    learning_rate: float = Field(gt=0)
    per_device_train_batch_size: int = Field(ge=1)
    per_device_eval_batch_size: int = Field(ge=1)
    gradient_accumulation_steps: int = Field(ge=1)
    warmup_ratio: float = Field(ge=0, lt=1)
    weight_decay: float = Field(ge=0)
    logging_steps: int = Field(ge=1)
    eval_steps: int = Field(ge=1)
    save_steps: int = Field(ge=1)
    lora_rank: int = Field(ge=1)
    lora_alpha: int = Field(ge=1)
    lora_dropout: float = Field(ge=0, lt=1)
    target_modules: list[str]

    @model_validator(mode="after")
    def precision_is_unambiguous(self) -> TrainingConfig:
        if self.bf16 and self.fp16:
            raise ValueError("training.bf16 and training.fp16 cannot both be true")
        return self


class PreferenceConfig(Section):
    enabled: bool
    output_dir: Path
    epochs: float = Field(gt=0)
    learning_rate: float = Field(gt=0)
    beta: float = Field(gt=0)


class EvaluationConfig(Section):
    maximum_regression_fraction: float = Field(ge=0, le=1)
    minimum_pass_rate: float = Field(ge=0, le=1)
    judge_model: str
    smoke_prompts: Path


class ExportConfig(Section):
    merged_dir: Path
    gguf_dir: Path
    ollama_model_name: str
    gguf_quantization: str
    mlc_dir: Path
    mlc_quantization: str
    mlc_context_window_size: int = Field(ge=2048)
    mlc_prefill_chunk_size: int = Field(ge=128)


class DistillConfig(Section):
    project: ProjectConfig
    paths: PathsConfig
    ingestion: IngestionConfig
    generation: GenerationConfig
    quality: QualityConfig
    split: SplitConfig
    training: TrainingConfig
    preference_training: PreferenceConfig
    evaluation: EvaluationConfig
    export: ExportConfig
    project_root: Path = Field(exclude=True)

    def resolve(self, path: Path) -> Path:
        return path if path.is_absolute() else self.project_root / path


def _deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    result = dict(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def load_config(path: str | Path, overlays: list[str | Path] | None = None) -> DistillConfig:
    root = project_root()
    config_path = Path(path)
    if not config_path.is_absolute():
        config_path = root / config_path
    payload = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    for overlay in overlays or []:
        overlay_path = Path(overlay)
        if not overlay_path.is_absolute():
            overlay_path = root / overlay_path
        overlay_payload = yaml.safe_load(overlay_path.read_text(encoding="utf-8")) or {}
        payload = _deep_merge(payload, overlay_payload)
    payload["project_root"] = root
    return DistillConfig.model_validate(payload)
