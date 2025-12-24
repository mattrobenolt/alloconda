from __future__ import annotations

import os
from dataclasses import dataclass
from types import ModuleType

import pytest

import fastproto._pure as pure

accelerated: ModuleType | None
try:
    import fastproto._accelerated as accelerated_mod
except ImportError:  # pragma: no cover - depends on native extension
    accelerated = None
else:
    accelerated = accelerated_mod


@dataclass(frozen=True)
class Backend:
    name: str
    Reader: type
    Writer: type


def _collect_backends() -> list[Backend]:
    force_pure = os.environ.get("FASTPROTO_FORCE_PURE")
    if force_pure and force_pure not in {"0", "false", "False"}:
        return [Backend("pure", pure.Reader, pure.Writer)]
    backends = [Backend("pure", pure.Reader, pure.Writer)]
    if accelerated is not None:
        backends.append(Backend("native", accelerated.Reader, accelerated.Writer))
    return backends


@pytest.fixture(
    scope="module", params=_collect_backends(), ids=lambda backend: backend.name
)
def backend(request: pytest.FixtureRequest) -> Backend:
    return request.param
