"""
Configuration Builder for ComfyUI
Assembles complete ComfyUI configurations with models, nodes, and workflows.
"""

import json
import logging
import shutil
import subprocess
from pathlib import Path
from typing import Dict, List, Optional

import yaml

logger = logging.getLogger('variant_builder')


class ConfigBuilder:
    """Builds ComfyUI configurations by assembling models, nodes, and workflows."""

    def __init__(self, base_dir: Path):
        self.base_dir = base_dir
        self.workflows_dir = base_dir / 'workflows'

        # Import other managers
        from model_manager import ModelManager
        from node_installer import NodeInstaller

        self.model_manager = ModelManager(base_dir)
        self.node_installer = NodeInstaller(base_dir)

    def build(self, config: Dict, config_name: str, output_dir: Optional[Path] = None) -> bool:
        """Build a complete configuration."""
        try:
            logger.info(f"Building config: {config_name}")

            if output_dir is None:
                output_dir = self.base_dir / 'build' / config_name

            # Create output directory
            output_dir.mkdir(parents=True, exist_ok=True)

            # Process nodes
            if not self._process_nodes(config.get('nodes', []), output_dir):
                return False

            # Process models
            if not self._process_models(config.get('models', {}), output_dir):
                return False

            # Process requirements
            if not self._process_requirements(config.get('requirements', []), output_dir):
                return False

            # Generate configuration file
            if not self._generate_config_file(config, config_name, output_dir):
                return False

            # Copy workflows
            if not self._copy_workflows(config, output_dir):
                return False

            # Generate Dockerfile if needed
            if config.get('generate_dockerfile', False):
                if not self._generate_dockerfile(config, variant_name, output_dir):
                    return False

            # Generate startup script
            if not self._generate_startup_script(config, config_name, output_dir):
                return False

            logger.info(f"Successfully built config: {config_name}")
            logger.info(f"Output directory: {output_dir}")

            return True

        except Exception as e:
            logger.error(f"Error building config: {e}")
            return False

    def _process_nodes(self, nodes: List, output_dir: Path) -> bool:
        """Process custom nodes for the configuration."""
        if not nodes:
            logger.info("No custom nodes to process")
            return True

        # Write nodes list
        nodes_file = output_dir / 'custom_nodes.json'
        with open(nodes_file, 'w') as f:
            json.dump(nodes, f, indent=2)
        logger.info(f"Wrote {len(nodes)} custom nodes to {nodes_file}")

        return True

    def _process_requirements(self, requirements: List[str], output_dir: Path) -> bool:
        """Process Python requirements for the configuration."""
        if not requirements:
            logger.info("No requirements to process")
            return True

        requirements_file = output_dir / 'requirements.txt'
        with open(requirements_file, 'w') as f:
            # Deduplicate requirements
            unique_requirements = list(set(requirements))
            f.write('\n'.join(unique_requirements))
        logger.info(f"Wrote {len(unique_requirements)} requirements to {requirements_file}")

        return True

    def _process_models(self, models: Dict, output_dir: Path) -> bool:
        """Process models for the configuration."""
        if not models:
            logger.info("No models to process")
            return True

        # Write model configuration
        models_file = output_dir / 'models.json'
        with open(models_file, 'w') as f:
            json.dump(models, f, indent=2)

        # Count total models
        total = sum(len(v) if isinstance(v, list) else 0 for v in models.values())
        logger.info(f"Wrote {total} models to {models_file}")

        return True

    def _generate_config_file(self, config: Dict, config_name: str, output_dir: Path) -> bool:
        """Generate the configuration file."""
        config_data = {
            'name': config_name,
            'version': config.get('version', '1.0.0'),
            'base_image': config.get('base_image', 'effekt/runpod-comfyui:base'),
            'env_vars': config.get('env_vars', {}),
            'nodes': config.get('nodes', []),
            'models': config.get('models', {}),
            'requirements': config.get('requirements', []),
            'workflows': config.get('workflows', [])
        }

        config_file = output_dir / 'config.yaml'
        with open(config_file, 'w') as f:
            yaml.dump(config_data, f, default_flow_style=False, sort_keys=False)

        logger.info(f"Generated configuration file: {config_file}")
        return True

    def _copy_workflows(self, config: Dict, output_dir: Path) -> bool:
        """Copy workflow files to the output directory."""
        workflows = config.get('workflows', [])

        if not workflows:
            logger.info("No workflows to copy")
            return True

        workflows_output = output_dir / 'workflows'
        workflows_output.mkdir(parents=True, exist_ok=True)

        # Copy workflow files
        for workflow in workflows:
            workflow_path = self.workflows_dir / workflow
            if workflow_path.exists():
                dest_path = workflows_output / workflow
                shutil.copy2(workflow_path, dest_path)
                logger.info(f"Copied workflow: {workflow}")
            else:
                logger.warning(f"Workflow not found: {workflow}")

        return True

    def _generate_dockerfile(self, config: Dict, config_name: str, output_dir: Path) -> bool:
        """Generate a Dockerfile for the configuration."""
        base_image = config.get('base_image', 'effekt/runpod-comfyui:base')

        dockerfile_content = f"""# Dockerfile for ComfyUI config: {config_name}
# Auto-generated by ComfyUI Builder

FROM {base_image}

# Set config name
ENV CONFIG_NAME={config_name}

# Copy configuration
COPY config.yaml /workspace/config.yaml
COPY custom_nodes.json /workspace/custom_nodes.json
COPY models.json /workspace/models.json

# Copy workflows
COPY workflows/ /workspace/ComfyUI/workflows/

# Install additional requirements
COPY requirements.txt /workspace/variant-requirements.txt
RUN pip install -r /workspace/variant-requirements.txt || true

# Copy startup script
COPY startup.sh /workspace/config-startup.sh
RUN chmod +x /workspace/config-startup.sh

# Set environment variables
"""
        for key, value in config.get('env_vars', {}).items():
            dockerfile_content += f"ENV {key}={value}\n"

        dockerfile_content += """
# Override entrypoint to use config startup
ENTRYPOINT ["/workspace/config-startup.sh"]
"""

        dockerfile_path = output_dir / 'Dockerfile'
        with open(dockerfile_path, 'w') as f:
            f.write(dockerfile_content)

        logger.info(f"Generated Dockerfile: {dockerfile_path}")
        return True

    def _generate_startup_script(self, config: Dict, config_name: str, output_dir: Path) -> bool:
        """Generate a startup script for the configuration."""
        script_content = """#!/bin/bash
set -e

echo "Starting ComfyUI config: """ + config_name + """"

# Source the base entrypoint functions if available
if [ -f "/workspace/entrypoint.sh" ]; then
    source /workspace/entrypoint.sh
fi

# Function to install custom nodes from JSON
install_custom_nodes() {
    if [ -f "/workspace/custom_nodes.json" ]; then
        echo "Installing custom nodes from config..."
        python3 -c "
import json
import subprocess
import sys

with open('/workspace/custom_nodes.json', 'r') as f:
    nodes = json.load(f)

for node in nodes:
    if isinstance(node, str):
        url = node
    else:
        url = node.get('url', '')

    if url:
        repo_name = url.rstrip('/').split('/')[-1].replace('.git', '')
        node_path = f'/workspace/ComfyUI/custom_nodes/{repo_name}'

        print(f'Installing: {repo_name}')
        result = subprocess.run(['git', 'clone', url, node_path], capture_output=True)
        if result.returncode != 0:
            print(f'Failed to install {repo_name}')

        # Install requirements if they exist
        req_file = f'{node_path}/requirements.txt'
        try:
            subprocess.run(['pip', 'install', '-r', req_file, '--quiet'], check=False)
        except:
            pass
"
    fi
}

# Function to download models from JSON
download_models() {
    if [ -f "/workspace/models.json" ] && [ "$DOWNLOAD_MODELS" = "true" ]; then
        echo "Downloading models from config..."
        python3 /workspace/download_models.py
    fi
}

# Main startup sequence
cd /workspace/ComfyUI

# Install custom nodes
install_custom_nodes

# Download models if enabled
download_models

# Copy workflows to ComfyUI directory
if [ -d "/workspace/workflows" ]; then
    cp -r /workspace/workflows/* /workspace/ComfyUI/workflows/ 2>/dev/null || true
fi

# Set variant-specific arguments
ARGS="--listen 0.0.0.0 --port 8188"

# Add config-specific ComfyUI arguments
if [ ! -z "$COMFYUI_CONFIG_ARGS" ]; then
    ARGS="$ARGS $COMFYUI_CONFIG_ARGS"
fi

# Add general ComfyUI arguments
if [ ! -z "$COMFYUI_ARGS" ]; then
    ARGS="$ARGS $COMFYUI_ARGS"
fi

echo "Starting ComfyUI with args: $ARGS"

# Start ComfyUI
exec python main.py $ARGS
"""

        startup_path = output_dir / 'startup.sh'
        with open(startup_path, 'w') as f:
            f.write(script_content)

        # Make it executable
        startup_path.chmod(0o755)

        logger.info(f"Generated startup script: {startup_path}")
        return True

    def create_docker_compose(self, config_name: str, output_dir: Path) -> bool:
        """Create a docker-compose.yml for the configuration."""
        compose_content = f"""version: '3.8'

services:
  comfyui-{config_name}:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: comfyui-{config_name}
    ports:
      - "8188:8188"
    volumes:
      - ./models:/workspace/ComfyUI/models
      - ./output:/workspace/ComfyUI/output
      - ./input:/workspace/ComfyUI/input
    environment:
      - DOWNLOAD_MODELS=${{DOWNLOAD_MODELS:-false}}
      - AUTO_UPDATE=${{AUTO_UPDATE:-false}}
      - COMFYUI_ARGS=${{COMFYUI_ARGS:-}}
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    restart: unless-stopped
"""

        compose_path = output_dir / 'docker-compose.yml'
        with open(compose_path, 'w') as f:
            f.write(compose_content)

        logger.info(f"Generated docker-compose.yml: {compose_path}")
        return True

    def build_docker_image(self, config_name: str, build_dir: Path, push: bool = False) -> bool:
        """Build a Docker image for the configuration."""
        try:
            image_tag = f"effekt/runpod-comfyui:{config_name}"

            logger.info(f"Building Docker image: {image_tag}")

            # Build the image
            cmd = ['docker', 'build', '-t', image_tag, str(build_dir)]
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode != 0:
                logger.error(f"Docker build failed: {result.stderr}")
                return False

            logger.info(f"Successfully built image: {image_tag}")

            if push:
                logger.info(f"Pushing image to registry...")
                cmd = ['docker', 'push', image_tag]
                result = subprocess.run(cmd, capture_output=True, text=True)

                if result.returncode != 0:
                    logger.error(f"Docker push failed: {result.stderr}")
                    return False

                logger.info(f"Successfully pushed image: {image_tag}")

            return True

        except Exception as e:
            logger.error(f"Error building Docker image: {e}")
            return False