from __future__ import annotations

import fnmatch
from pathlib import Path, PurePosixPath

import yaml
from rich.console import Console

from .chunking import chunk_text
from .config import DistillConfig
from .io import load_text, sha256_file, sha256_text, write_json_atomic, write_jsonl_atomic
from .schemas import ChunkRecord, DocumentRecord, SourceManifest


def _matches(path: str, patterns: list[str]) -> bool:
    candidate = PurePosixPath(path).as_posix()
    return any(fnmatch.fnmatch(candidate, pattern) for pattern in patterns)


def _collect_files(source_root: Path, include: list[str], exclude: list[str]) -> list[Path]:
    found: dict[str, Path] = {}
    for pattern in include:
        for path in source_root.glob(pattern):
            if not path.is_file():
                continue
            relative = path.relative_to(source_root).as_posix()
            if _matches(relative, exclude):
                continue
            found[relative] = path
    return [found[key] for key in sorted(found)]


def ingest_sources(config: DistillConfig, console: Console | None = None) -> dict:
    console = console or Console()
    manifest_path = config.resolve(config.paths.source_manifest)
    raw = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
    manifest = SourceManifest.model_validate(raw)
    documents: list[DocumentRecord] = []
    chunks: list[ChunkRecord] = []
    rejected: list[dict] = []
    included_extensions = {item.lower() for item in config.ingestion.include_extensions}

    for source in manifest.sources:
        source_root = Path(source.path)
        if not source_root.is_absolute():
            source_root = (manifest_path.parent / source_root).resolve()
        if not source_root.exists():
            raise FileNotFoundError(f"Source root does not exist: {source_root}")

        console.print(f"[cyan]Ingesting[/cyan] {source.id}: {source_root}")
        for path in _collect_files(source_root, source.include, source.exclude):
            if path.suffix.lower() not in included_extensions:
                continue
            relative = path.relative_to(source_root).as_posix()
            text = load_text(path).replace("\x00", "")
            if not text.strip():
                rejected.append({"source_id": source.id, "path": relative, "reason": "empty"})
                continue
            file_hash = sha256_file(path)
            document_id = sha256_text(f"{source.id}\0{relative}\0{file_hash}")[:24]
            documents.append(
                DocumentRecord(
                    document_id=document_id,
                    source_id=source.id,
                    relative_path=relative,
                    source_sha256=file_hash,
                    license=source.license,
                    rights_basis=source.rights_basis,
                    redistributable=source.redistributable,
                    characters=len(text),
                )
            )
            for ordinal, (start, end, content) in enumerate(
                chunk_text(
                    text,
                    config.ingestion.chunk_characters,
                    config.ingestion.overlap_characters,
                )
            ):
                content_hash = sha256_text(content)
                chunks.append(
                    ChunkRecord(
                        chunk_id=sha256_text(f"{document_id}\0{ordinal}\0{content_hash}")[:28],
                        document_id=document_id,
                        source_id=source.id,
                        relative_path=relative,
                        source_sha256=file_hash,
                        chunk_sha256=content_hash,
                        ordinal=ordinal,
                        start_character=start,
                        end_character=end,
                        text=content,
                        license=source.license,
                        rights_basis=source.rights_basis,
                        redistributable=source.redistributable,
                    )
                )

    work_dir = config.resolve(config.paths.work_dir)
    write_jsonl_atomic(work_dir / "documents.jsonl", (item.model_dump() for item in documents))
    write_jsonl_atomic(work_dir / "chunks.jsonl", (item.model_dump() for item in chunks))
    audit = {
        "manifest": str(manifest_path),
        "documents": len(documents),
        "chunks": len(chunks),
        "rejected": rejected,
        "all_sources_have_rights_basis": all(source.rights_basis for source in manifest.sources),
    }
    write_json_atomic(work_dir / "ingestion_audit.json", audit)
    console.print(f"[green]Ingested {len(documents)} documents into {len(chunks)} chunks.[/green]")
    return audit
