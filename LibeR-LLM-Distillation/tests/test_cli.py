from liber_distill.cli import main


def test_doctor_parser_help(capsys):
    try:
        main(["--help"])
    except SystemExit as exc:
        assert exc.code == 0
    assert "build-training-data" in capsys.readouterr().out
