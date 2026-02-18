"""Abstract base class for SOP export adapters.

Defines the contract that all SOP export adapters must implement.
This allows OpenMimic to support multiple output targets (OpenClaw,
generic filesystem, future cloud backends, etc.) through a pluggable
adapter pattern.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path


class SOPExportAdapter(ABC):
    """Abstract base for SOP export adapters.

    All adapters must implement these methods to write SOPs,
    metadata, and provide directory information.
    """

    @abstractmethod
    def write_sop(self, sop_template: dict) -> Path:
        """Write a single SOP and return the path to the written file."""
        ...

    @abstractmethod
    def write_all_sops(self, sop_templates: list[dict]) -> list[Path]:
        """Write multiple SOPs and return paths to all written files."""
        ...

    @abstractmethod
    def write_metadata(self, metadata_type: str, data: dict) -> Path:
        """Write a metadata file and return its path."""
        ...

    @abstractmethod
    def get_sops_dir(self) -> Path:
        """Return the directory where SOPs are stored."""
        ...

    @abstractmethod
    def list_sops(self) -> list[dict]:
        """List all SOPs with summary info (slug, title, path, confidence)."""
        ...
