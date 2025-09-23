#!/usr/bin/env python3
"""
YAML configuration loader using HiYaPyCo for hierarchical configs.
Handles extending and merging configurations properly.
"""

import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

import hiyapyco
import yaml

logger = logging.getLogger(__name__)


class ConfigLoader:
    """Loads YAML configurations with inheritance using HiYaPyCo."""

    def __init__(self, config_dir: Path):
        """Initialize the config loader.

        Args:
            config_dir: Directory containing configuration files
        """
        self.config_dir = config_dir
        self._cache = {}

    def load_config(self, config_name: str) -> Dict[str, Any]:
        """Load a configuration with inheritance support.

        Args:
            config_name: Name of the configuration (without 'config-' prefix and '.yaml' suffix)

        Returns:
            Loaded and merged configuration
        """
        if config_name in self._cache:
            return self._cache[config_name]

        config_path = self.config_dir / f'config-{config_name}.yaml'

        if not config_path.exists():
            raise FileNotFoundError(f"Config not found: {config_name}")

        # Build list of config files to merge
        config_files = []

        # Check if this config extends another
        with open(config_path, 'r') as f:
            temp_config = yaml.safe_load(f)

        if 'extends' in temp_config:
            base_name = temp_config['extends']
            if base_name.startswith('config-'):
                base_name = base_name[7:]
            if base_name.endswith('.yaml'):
                base_name = base_name[:-5]

            # Add base config file path
            base_path = self.config_dir / f'config-{base_name}.yaml'
            if base_path.exists():
                config_files.append(str(base_path))

        # Add current config file
        config_files.append(str(config_path))

        # Use HiYaPyCo to merge all configs
        if len(config_files) > 1:
            merged = hiyapyco.load(
                config_files,
                method=hiyapyco.METHOD_MERGE,
                mergelists=False,  # Append lists instead of merging
                interpolate=False,
                failonmissingfiles=True
            )
        else:
            # Single file, just load it
            with open(config_path, 'r') as f:
                merged = yaml.safe_load(f)

        # Remove the extends field if present
        if 'extends' in merged:
            del merged['extends']

        self._cache[config_name] = merged
        return merged

    def load_configs_with_hierarchy(self, *config_names: str) -> Dict[str, Any]:
        """Load and merge multiple configs in order.

        Args:
            config_names: Names of configs to load and merge (in order)

        Returns:
            Merged configuration
        """
        configs = []
        for name in config_names:
            config_path = self.config_dir / f'config-{name}.yaml'
            if config_path.exists():
                configs.append(str(config_path))

        if not configs:
            raise ValueError("No valid config files found")

        # Use HiYaPyCo to merge all configs
        return hiyapyco.load(
            configs,
            method=hiyapyco.METHOD_MERGE,
            interpolate=False,
            failonmissingfiles=False
        )