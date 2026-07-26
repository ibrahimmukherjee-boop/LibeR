from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from rich.console import Console

from .config import load_config, project_root
from .dataset import build_datasets
from .doctor import run_doctor
from .evaluate import evaluate
from .export import export_mlc, export_ollama
from .generate import adjudicate_candidates, generate_candidates
from .ingest import ingest_sources
from .training import merge_adapter, train_dpo, train_sft


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="liber-distill",
        description="Build and validate a compact, locally distilled LibeR assistant.",
    )
    parser.add_argument(
        "--config", default="configs/default.yaml", help="Primary YAML configuration."
    )
    parser.add_argument(
        "--overlay",
        action="append",
        default=[],
        help="YAML overlay applied after the primary config; may be repeated.",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("doctor", help="Check Python, Ollama, GPU and training dependencies.")
    sub.add_parser("ingest", help="Ingest licensed sources into hashed chunks.")
    generate = sub.add_parser("generate", help="Generate grounded candidates with the teacher.")
    generate.add_argument("--limit", type=int)
    adjudicate = sub.add_parser("adjudicate", help="Independently judge and repair candidates.")
    adjudicate.add_argument("--limit", type=int)
    adjudicate.add_argument(
        "--force",
        action="store_true",
        help="Append fresh decisions for existing candidates; latest decision wins.",
    )
    sub.add_parser("build-dataset", help="Filter, deduplicate and leakage-safely split data.")
    pipeline = sub.add_parser(
        "build-training-data", help="Run ingest, generation, adjudication and dataset build."
    )
    pipeline.add_argument("--limit", type=int)
    sft = sub.add_parser("train-sft", help="Run QLoRA supervised fine-tuning.")
    sft.add_argument("--resume", nargs="?", const=True, default=False)
    dpo = sub.add_parser("train-dpo", help="Run optional preference optimisation.")
    dpo.add_argument("--resume", nargs="?", const=True, default=False)
    evaluate_parser = sub.add_parser(
        "evaluate", help="Compare the base and tuned models against held-out gates."
    )
    evaluate_parser.add_argument("--with-judge", action="store_true")
    merge = sub.add_parser("merge", help="Merge the final LoRA adapter into the base model.")
    merge.add_argument("--adapter", type=Path)
    merge.add_argument(
        "--allow-unvalidated",
        action="store_true",
        help="Permit a development merge without a passing evaluation record.",
    )
    ollama = sub.add_parser("export-ollama", help="Export GGUF and register it in Ollama.")
    ollama.add_argument("--llama-cpp-dir", type=Path, required=True)
    ollama.add_argument("--no-create", action="store_true")
    mlc = sub.add_parser("export-webllm", help="Compile the merged model for MLC/WebLLM.")
    mlc.add_argument("--weights-only", action="store_true")
    sub.add_parser("init-local-config", help="Create ignored configs/local.yaml from the default.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    console = Console()
    if args.command == "init-local-config":
        destination = project_root() / "configs" / "local.yaml"
        if destination.exists():
            raise FileExistsError(f"Refusing to overwrite {destination}")
        shutil.copy2(project_root() / "configs" / "default.yaml", destination)
        console.print(f"[green]Created {destination}[/green]")
        return 0

    config = load_config(args.config, args.overlay)
    if args.command == "doctor":
        run_doctor(config, console)
    elif args.command == "ingest":
        ingest_sources(config, console)
    elif args.command == "generate":
        generate_candidates(config, console, args.limit)
    elif args.command == "adjudicate":
        adjudicate_candidates(config, console, args.limit, args.force)
    elif args.command == "build-dataset":
        build_datasets(config, console)
    elif args.command == "build-training-data":
        ingest_sources(config, console)
        generate_candidates(config, console, args.limit)
        adjudicate_candidates(config, console, args.limit)
        build_datasets(config, console)
    elif args.command == "train-sft":
        train_sft(config, console, args.resume)
    elif args.command == "train-dpo":
        train_dpo(config, console, args.resume)
    elif args.command == "evaluate":
        evaluate(config, console, args.with_judge)
    elif args.command == "merge":
        merge_adapter(config, console, args.adapter, args.allow_unvalidated)
    elif args.command == "export-ollama":
        export_ollama(config, args.llama_cpp_dir, console, create_model=not args.no_create)
    elif args.command == "export-webllm":
        export_mlc(config, console, compile_library=not args.weights_only)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
