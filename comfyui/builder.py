#!/usr/bin/env python3
"""
ComfyUI Variant Builder CLI
Manages ComfyUI variants with different model packages, custom nodes, and workflows.
"""

import argparse
import json
import logging
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional

import yaml

# Add lib directory to path
sys.path.insert(0, str(Path(__file__).parent / 'lib'))

try:
    from config_loader_hiyapyco import ConfigLoader
except ImportError:
    # Fallback to simple loader if HiYaPyCo is not available
    logger.warning("HiYaPyCo not available, using simple config loader")
    from config_loader_simple import ConfigLoader
from model_manager import ModelManager
from node_installer import NodeInstaller
from variant_builder import ConfigBuilder

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('comfyui-builder')


class ComfyUIBuilder:
    """Main CLI class for ComfyUI configuration management."""

    def __init__(self):
        self.base_dir = Path(__file__).parent
        # Look for configs in configs/ subdirectory
        self.configs_dir = self.base_dir / 'configs'
        if not self.configs_dir.exists():
            # Fallback to base_dir if configs/ doesn't exist
            self.configs_dir = self.base_dir
        self.workflows_dir = self.base_dir / 'workflows'
        self.config_loader = ConfigLoader(self.configs_dir)
        self.model_manager = ModelManager(self.base_dir)
        self.node_installer = NodeInstaller(self.base_dir)
        self.config_builder = ConfigBuilder(self.base_dir)

    def load_yaml(self, path: Path) -> Dict:
        """Load a YAML configuration file."""
        # Use the config loader for files in the configs directory
        if path.parent == self.configs_dir and path.name.startswith('config-'):
            config_name = path.stem.replace('config-', '')
            return self.config_loader.load_config(config_name)
        else:
            # Fallback to regular YAML loading for other files
            with open(path, 'r') as f:
                return yaml.safe_load(f)

    def save_yaml(self, data: Dict, path: Path):
        """Save data to a YAML file."""
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False)

    def list_configs(self) -> List[str]:
        """List all available configurations."""
        configs = []
        for f in self.configs_dir.glob('config-*.yaml'):
            config_name = f.stem.replace('config-', '')
            configs.append(config_name)
        return sorted(configs)

    def validate_config(self, config_name: str) -> bool:
        """Validate a configuration."""
        try:
            config_path = self.configs_dir / f'config-{config_name}.yaml'
            if not config_path.exists():
                logger.error(f"Config not found: {config_name}")
                return False

            # Use config loader to handle inheritance
            config = self.config_loader.load_config(config_name)

            # Basic validation
            required_fields = ['name', 'version']
            for field in required_fields:
                if field not in config:
                    logger.error(f"Missing required field: {field}")
                    return False

            # Validate nodes if present
            nodes = config.get('nodes', [])
            for node in nodes:
                if isinstance(node, dict) and 'url' not in node:
                    logger.error(f"Node missing URL: {node}")
                    return False

            # Validate models if present
            models = config.get('models', {})
            for model_type, model_list in models.items():
                for model in model_list:
                    if 'url' not in model or 'name' not in model:
                        logger.error(f"Model missing required fields: {model}")
                        return False

            logger.info(f"Config {config_name} is valid")
            return True

        except Exception as e:
            logger.error(f"Error validating variant: {e}")
            return False

    def build_config(self, config_name: str, output_dir: Optional[Path] = None) -> bool:
        """Build a specific configuration."""
        logger.info(f"Building config: {config_name}")

        if not self.validate_config(config_name):
            return False

        try:
            # Use config loader to handle inheritance
            config = self.config_loader.load_config(config_name)

            # Use config builder to assemble the config
            return self.config_builder.build(
                config=config,
                config_name=config_name,
                output_dir=output_dir
            )

        except Exception as e:
            logger.error(f"Error building variant: {e}")
            return False

    def install_nodes(self, config_name: str) -> bool:
        """Install custom nodes from configuration."""
        try:
            config_path = self.configs_dir / f'config-{config_name}.yaml'
            if not config_path.exists():
                logger.error(f"Config not found: {config_name}")
                return False

            # Use config loader to handle inheritance
            config = self.config_loader.load_config(config_name)
            nodes = config.get('nodes', [])

            if not nodes:
                logger.info("No nodes to install")
                return True

            logger.info(f"Installing nodes for config: {config_name}")

            for node in nodes:
                if isinstance(node, dict):
                    success = self.node_installer.install_node(
                        node['url'],
                        branch=node.get('branch')  # Pass branch if specified, not description
                    )
                elif isinstance(node, str):
                    success = self.node_installer.install_node(node)

                if not success:
                    logger.warning(f"Failed to install node: {node}")

            return True

        except Exception as e:
            logger.error(f"Failed to install nodes: {str(e)}")
            return False

    def download_models(self, config_name: str, output_dir: Optional[Path] = None) -> bool:
        """Download models for a configuration."""
        try:
            config_path = self.configs_dir / f'config-{config_name}.yaml'
            if not config_path.exists():
                logger.error(f"Config not found: {config_name}")
                return False

            # Use config loader to handle inheritance
            config = self.config_loader.load_config(config_name)
            models = config.get('models', {})

            if not models:
                logger.info("No models to download")
                return True

            # Convert models dict to collection format
            collection_config = {
                'name': f'{config_name}-models',
                'models': models
            }

            logger.info(f"Downloading models for config: {config_name}")

            return self.model_manager.download_collection(
                collection_config,
                output_dir=output_dir
            )

        except Exception as e:
            logger.error(f"Error downloading models: {e}")
            return False

    def create_config(self, name: str, base_image: str = 'effekt/runpod-comfyui:base') -> bool:
        """Create a new configuration."""
        config_path = self.configs_dir / f'config-{name}.yaml'

        if config_path.exists():
            logger.error(f"Config already exists: {name}")
            return False

        config_data = {
            'name': name,
            'version': '1.0.0',
            'base_image': base_image,
            'description': f'ComfyUI configuration: {name}',
            'extends': 'config-base.yaml',  # Inherit from base by default
            'nodes': [
                '!include base',  # Include all base nodes
                # Add custom nodes here
            ],
            'requirements': [
                '!include base',  # Include base requirements
                # Add custom requirements here
            ],
            'workflows': [],
            'models': {
                'checkpoints': [],
                'loras': [],
                'vae': [],
                'controlnet': [],
                'upscale_models': []
            },
            'env_vars': {
                'CONFIG_NAME': name,
                'COMFYUI_ARGS': ''
            }
        }

        self.save_yaml(config_data, config_path)
        logger.info(f"Created config template: {config_path}")
        return True


def main():
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(
        description='ComfyUI Configuration Manager',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # List command
    list_parser = subparsers.add_parser('list', help='List available configurations')

    # Validate command
    validate_parser = subparsers.add_parser('validate', help='Validate a configuration')
    validate_parser.add_argument('config', help='Configuration name to validate')

    # Build command
    build_parser = subparsers.add_parser('build', help='Build a configuration')
    build_parser.add_argument('config', help='Configuration name to build')
    build_parser.add_argument(
        '--output', '-o',
        type=Path,
        help='Output directory for build artifacts'
    )

    # Install nodes command
    install_nodes_parser = subparsers.add_parser('install-nodes', help='Install custom nodes')
    install_nodes_parser.add_argument('--config', help='Configuration file path', required=True)

    # Download command
    download_parser = subparsers.add_parser('download', help='Download models')
    download_parser.add_argument('--config', help='Configuration file path', required=True)
    download_parser.add_argument(
        '--output', '-o',
        type=Path,
        help='Output directory for models'
    )

    # Create command
    create_parser = subparsers.add_parser('create', help='Create a new configuration')
    create_parser.add_argument('name', help='Configuration name')
    create_parser.add_argument(
        '--base-image', '-b',
        default='effekt/runpod-comfyui:base',
        help='Base Docker image'
    )

    # Parse arguments
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    # Initialize builder
    builder = ComfyUIBuilder()

    # Execute commands
    if args.command == 'list':
        configs = builder.list_configs()
        if configs:
            print("Available configurations:")
            for c in configs:
                print(f"  - {c}")
        else:
            print("No configurations found")

    elif args.command == 'validate':
        success = builder.validate_config(args.config)
        return 0 if success else 1

    elif args.command == 'build':
        success = builder.build_config(args.config, args.output)
        return 0 if success else 1

    elif args.command == 'install-nodes':
        # Parse config file path to get config name
        config_path = Path(args.config)
        if config_path.name.startswith('config-') and config_path.name.endswith('.yaml'):
            config_name = config_path.name[7:-5]  # Remove 'config-' and '.yaml'
        else:
            config_name = config_path.stem
        success = builder.install_nodes(config_name)
        return 0 if success else 1

    elif args.command == 'download':
        # Parse config file path to get config name
        config_path = Path(args.config)
        if config_path.name.startswith('config-') and config_path.name.endswith('.yaml'):
            config_name = config_path.name[7:-5]  # Remove 'config-' and '.yaml'
        else:
            config_name = config_path.stem
        success = builder.download_models(config_name, args.output)
        return 0 if success else 1

    elif args.command == 'create':
        success = builder.create_config(args.name, args.base_image)
        return 0 if success else 1

    return 0


if __name__ == '__main__':
    sys.exit(main())