"""Guarded CycleCloud Slurm headless-template transformation."""

from .transform import TransformError, transform_template

__all__ = ["TransformError", "transform_template"]
