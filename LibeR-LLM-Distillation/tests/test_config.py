import yaml

from liber_distill.config import load_config
from liber_distill.schemas import SourceManifest


def test_default_configuration_is_valid():
    config = load_config("configs/default.yaml", ["configs/hardware/rtx5060-8gb.yaml"])
    assert config.training.student_model == "Qwen/Qwen3-1.7B"
    assert config.training.load_in_4bit is True
    assert config.split.group_by == "document"


def test_ecosystem_source_manifest_is_valid():
    config = load_config("configs/default.yaml", ["configs/ecosystem-sources.yaml"])
    path = config.resolve(config.paths.source_manifest)
    manifest = SourceManifest.model_validate(yaml.safe_load(path.read_text(encoding="utf-8")))
    assert {source.id for source in manifest.sources} == {
        "ecosystem-docs",
        "liberality",
        "liberary",
        "liberation",
        "liberator",
        "libertad",
        "liberties",
    }
