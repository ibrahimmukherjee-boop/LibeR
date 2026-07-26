from __future__ import annotations

import json
import time
from typing import TypeVar

import httpx
from pydantic import BaseModel, ValidationError

T = TypeVar("T", bound=BaseModel)


class OllamaError(RuntimeError):
    pass


def _ollama_schema(model: type[BaseModel]) -> dict:
    """Reduce Pydantic JSON Schema to Ollama's portable grammar subset."""
    schema = model.model_json_schema()
    unsupported = {
        "default",
        "description",
        "examples",
        "maxItems",
        "maxLength",
        "maximum",
        "minItems",
        "minLength",
        "minimum",
        "title",
    }

    def clean(value: object) -> None:
        if isinstance(value, dict):
            for key in list(value):
                if key in unsupported:
                    value.pop(key, None)
                else:
                    clean(value[key])
            if value.get("type") == "object" and isinstance(value.get("properties"), dict):
                value["required"] = list(value["properties"])
        elif isinstance(value, list):
            for item in value:
                clean(item)

    clean(schema)
    return schema


class OllamaClient:
    def __init__(
        self,
        base_url: str,
        timeout_seconds: float,
        max_retries: int,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = httpx.Timeout(timeout_seconds)
        self.max_retries = max_retries

    def list_models(self) -> list[str]:
        try:
            response = httpx.get(f"{self.base_url}/api/tags", timeout=10)
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise OllamaError(f"Cannot contact Ollama at {self.base_url}: {exc}") from exc
        return [item["name"] for item in response.json().get("models", [])]

    def chat_json(
        self,
        *,
        model: str,
        system: str,
        user: str,
        response_type: type[T],
        options: dict,
        think: bool = False,
    ) -> T:
        payload = {
            "model": model,
            "stream": False,
            "think": think,
            "keep_alive": "15m",
            "format": _ollama_schema(response_type),
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "options": options,
        }
        last_error: Exception | None = None
        for attempt in range(self.max_retries + 1):
            try:
                response = httpx.post(
                    f"{self.base_url}/api/chat", json=payload, timeout=self.timeout
                )
                if response.is_error:
                    raise OllamaError(f"HTTP {response.status_code}: {response.text[:1000]}")
                body = response.json()
                content = body["message"]["content"]
                if not content.strip():
                    reason = body.get("done_reason", "unknown")
                    thinking = bool(body.get("message", {}).get("thinking"))
                    raise ValueError(
                        "Ollama returned no final content "
                        f"(done_reason={reason}, thinking_present={thinking}). "
                        "Disable generation.think or increase num_predict."
                    )
                parsed = json.loads(content)
                return response_type.model_validate(parsed)
            except (
                httpx.HTTPError,
                KeyError,
                ValueError,
                ValidationError,
                OllamaError,
            ) as exc:
                last_error = exc
                if attempt < self.max_retries:
                    time.sleep(min(2**attempt, 8))
        raise OllamaError(
            f"{model} did not return valid structured output after "
            f"{self.max_retries + 1} attempt(s): {last_error}"
        )
