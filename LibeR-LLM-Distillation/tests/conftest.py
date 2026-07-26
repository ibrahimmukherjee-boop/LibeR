from pathlib import Path

import pytest

from liber_distill.config import load_config


@pytest.fixture
def temp_config(tmp_path: Path):
    config = load_config("configs/smoke.yaml")
    paths = config.paths.model_copy(
        update={
            "work_dir": tmp_path / "work",
            "dataset_dir": tmp_path / "datasets",
            "run_dir": tmp_path / "runs",
            "export_dir": tmp_path / "exports",
        }
    )
    return config.model_copy(update={"paths": paths})
