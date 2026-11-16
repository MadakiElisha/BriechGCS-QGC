import sys
from pathlib import Path

import pytest

EDGE_DIR = Path(__file__).resolve().parent.parent
REPO = EDGE_DIR.parent
sys.path.insert(0, str(EDGE_DIR))
sys.path.insert(0, str(REPO / "ground-core"))

from coordinator.schemas import MessageValidator  # noqa: E402


@pytest.fixture(scope="session")
def validator() -> MessageValidator:
    """The coordinator's own check: the edge is held to the same schemas as every other sender."""
    return MessageValidator(REPO / "schemas")
