from liber_distill.ollama import _ollama_schema
from liber_distill.schemas import GroundedAnswer


def test_ollama_schema_requires_all_fields_and_removes_unsupported_constraints():
    schema = _ollama_schema(GroundedAnswer)
    assert set(schema["required"]) == set(schema["properties"])

    unsupported = {
        "default",
        "maxItems",
        "maxLength",
        "maximum",
        "minItems",
        "minLength",
        "minimum",
        "title",
    }

    def walk(value):
        if isinstance(value, dict):
            assert not (unsupported & set(value))
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(schema)
