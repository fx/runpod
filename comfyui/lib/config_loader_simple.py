#!/usr/bin/env python3
"""
Simple YAML configuration loader - fallback when HiYaPyCo is not available.
Provides basic inheritance support through manual merging.
"""

import logging
from pathlib import Path
from typing import Any, Dict, List

import yaml

logger = logging.getLogger(__name__)


class ConfigLoader:
    """Simple config loader with basic inheritance support."""

    def __init__(self, config_dir: Path):
        """Initialize the config loader.

        Args:
            config_dir: Directory containing configuration files
        """
        self.config_dir = config_dir
        self._cache = {}

    def _merge_lists(self, base: List, override: List) -> List:
        """Merge two lists by concatenating them."""
        return base + override

    def _merge_dicts(self, base: Dict, override: Dict) -> Dict:
        """Deep merge two dictionaries."""
        result = base.copy()

        for key, value in override.items():
            if key in result:
                if isinstance(result[key], dict) and isinstance(value, dict):
                    # Recursively merge dictionaries
                    result[key] = self._merge_dicts(result[key], value)
                elif isinstance(result[key], list) and isinstance(value, list):
                    # Concatenate lists
                    result[key] = self._merge_lists(result[key], value)
                else:
                    # Override value
                    result[key] = value
            else:
                result[key] = value

        return result

    def load_config(self, config_name: str) -> Dict[str, Any]:
        """Load a configuration with basic inheritance support.

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

        # Load the config file
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)

        # Check if this config extends another
        if 'extends' in config:
            base_name = config['extends']
            if base_name.startswith('config-'):
                base_name = base_name[7:]
            if base_name.endswith('.yaml'):
                base_name = base_name[:-5]

            # Load base config recursively
            base_config = self.load_config(base_name)

            # Remove the extends field before merging
            del config['extends']

            # Merge configurations
            config = self._merge_dicts(base_config, config)

        self._cache[config_name] = config
        return config