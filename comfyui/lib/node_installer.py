"""
Node Installer for ComfyUI Builder
Manages installation of ComfyUI custom nodes.
"""

import json
import logging
import os
import shutil
import subprocess
from pathlib import Path
from typing import Dict, List, Optional

logger = logging.getLogger('node_installer')


class NodeInstaller:
    """Manages ComfyUI custom node installations."""

    def __init__(self, base_dir: Path):
        self.base_dir = base_dir
        # ComfyUI is installed in a subdirectory
        comfyui_dir = base_dir / 'ComfyUI'
        if comfyui_dir.exists():
            self.nodes_dir = comfyui_dir / 'custom_nodes'
        else:
            # Fallback for local development
            self.nodes_dir = base_dir / 'custom_nodes'
        self.nodes_dir.mkdir(parents=True, exist_ok=True)

    def install_nodes_from_package(self, package_config: Dict) -> bool:
        """Install all custom nodes defined in a package."""
        nodes = package_config.get('custom_nodes', [])
        if not nodes:
            logger.info("No custom nodes to install")
            return True

        success = True
        for node in nodes:
            if isinstance(node, str):
                # Simple URL format
                if not self.install_node(node):
                    success = False
            elif isinstance(node, dict):
                # Detailed node configuration
                url = node.get('url')
                branch = node.get('branch')
                commit = node.get('commit')
                if url and not self.install_node(url, branch=branch, commit=commit):
                    success = False

        # Install requirements after all nodes are cloned
        if success:
            self.install_all_requirements()

        return success

    def install_node(self, url: str, branch: Optional[str] = None, commit: Optional[str] = None) -> bool:
        """Install a single custom node from a git repository."""
        try:
            # Extract repository name from URL
            repo_name = url.rstrip('/').split('/')[-1]
            if repo_name.endswith('.git'):
                repo_name = repo_name[:-4]

            node_path = self.nodes_dir / repo_name

            # Check if already installed
            if node_path.exists():
                logger.info(f"Node already installed: {repo_name}")
                return self.update_node(node_path, branch=branch, commit=commit)

            logger.info(f"Installing custom node: {repo_name}")

            # Ensure URL is properly formatted for public repos
            if url.startswith('https://github.com/') and not url.endswith('.git'):
                url = f"{url}.git"

            # Clone the repository
            cmd = ['git', 'clone', '--depth', '1']  # Shallow clone for faster installation
            if branch:
                cmd.extend(['-b', branch])
            cmd.extend([url, str(node_path)])

            logger.debug(f"Running: {' '.join(cmd)}")

            # Set environment to avoid credential prompts for public repos
            env = os.environ.copy()
            env['GIT_TERMINAL_PROMPT'] = '0'  # Disable git credential prompts

            result = subprocess.run(cmd, capture_output=True, text=True, env=env)
            if result.returncode != 0:
                logger.error(f"Failed to clone {repo_name}: {result.stderr}")
                return False

            # Checkout specific commit if provided
            if commit:
                result = subprocess.run(
                    ['git', 'checkout', commit],
                    cwd=node_path,
                    capture_output=True,
                    text=True
                )
                if result.returncode != 0:
                    logger.error(f"Failed to checkout commit {commit}: {result.stderr}")
                    return False

            logger.info(f"Successfully installed: {repo_name}")
            return True

        except Exception as e:
            logger.error(f"Error installing node from {url}: {e}")
            return False

    def update_node(self, node_path: Path, branch: Optional[str] = None, commit: Optional[str] = None) -> bool:
        """Update an existing custom node."""
        try:
            logger.info(f"Updating node: {node_path.name}")

            # Set environment to avoid credential prompts
            env = os.environ.copy()
            env['GIT_TERMINAL_PROMPT'] = '0'

            # Fetch latest changes
            result = subprocess.run(
                ['git', 'fetch', '--all'],
                cwd=node_path,
                capture_output=True,
                text=True,
                env=env
            )
            if result.returncode != 0:
                logger.warning(f"Failed to fetch updates for {node_path.name}")
                return True  # Not critical

            # Checkout branch or commit if specified
            if branch:
                result = subprocess.run(
                    ['git', 'checkout', branch],
                    cwd=node_path,
                    capture_output=True,
                    text=True
                )
                if result.returncode == 0:
                    subprocess.run(
                        ['git', 'pull', 'origin', branch],
                        cwd=node_path,
                        capture_output=True,
                        text=True
                    )
            elif commit:
                subprocess.run(
                    ['git', 'checkout', commit],
                    cwd=node_path,
                    capture_output=True,
                    text=True
                )

            return True

        except Exception as e:
            logger.error(f"Error updating node {node_path}: {e}")
            return False

    def remove_node(self, node_name: str) -> bool:
        """Remove a custom node."""
        try:
            node_path = self.nodes_dir / node_name
            if not node_path.exists():
                logger.warning(f"Node not found: {node_name}")
                return False

            logger.info(f"Removing node: {node_name}")
            shutil.rmtree(node_path)
            logger.info(f"Successfully removed: {node_name}")
            return True

        except Exception as e:
            logger.error(f"Error removing node {node_name}: {e}")
            return False

    def install_all_requirements(self) -> bool:
        """Install Python requirements for all custom nodes."""
        logger.info("Installing requirements for all custom nodes")
        success = True

        for node_dir in self.nodes_dir.iterdir():
            if not node_dir.is_dir():
                continue

            requirements_file = node_dir / 'requirements.txt'
            if requirements_file.exists():
                if not self.install_requirements(requirements_file):
                    success = False

        return success

    def install_requirements(self, requirements_file: Path) -> bool:
        """Install Python requirements from a requirements.txt file."""
        try:
            logger.info(f"Installing requirements from: {requirements_file}")

            result = subprocess.run(
                ['pip', 'install', '-r', str(requirements_file), '--quiet'],
                capture_output=True,
                text=True
            )

            if result.returncode != 0:
                logger.error(f"Failed to install requirements: {result.stderr}")
                return False

            return True

        except Exception as e:
            logger.error(f"Error installing requirements from {requirements_file}: {e}")
            return False

    def list_installed_nodes(self) -> List[Dict]:
        """List all installed custom nodes."""
        nodes = []

        for node_dir in self.nodes_dir.iterdir():
            if not node_dir.is_dir():
                continue

            node_info = {
                'name': node_dir.name,
                'path': str(node_dir),
            }

            # Try to get git info
            try:
                # Get remote URL
                result = subprocess.run(
                    ['git', 'config', '--get', 'remote.origin.url'],
                    cwd=node_dir,
                    capture_output=True,
                    text=True
                )
                if result.returncode == 0:
                    node_info['url'] = result.stdout.strip()

                # Get current branch
                result = subprocess.run(
                    ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
                    cwd=node_dir,
                    capture_output=True,
                    text=True
                )
                if result.returncode == 0:
                    node_info['branch'] = result.stdout.strip()

                # Get current commit
                result = subprocess.run(
                    ['git', 'rev-parse', 'HEAD'],
                    cwd=node_dir,
                    capture_output=True,
                    text=True
                )
                if result.returncode == 0:
                    node_info['commit'] = result.stdout.strip()[:8]

            except:
                pass

            # Check for requirements.txt
            if (node_dir / 'requirements.txt').exists():
                node_info['has_requirements'] = True

            nodes.append(node_info)

        return nodes

    def validate_node(self, node_path: Path) -> bool:
        """Validate that a custom node is properly installed."""
        if not node_path.exists():
            return False

        # Check for __init__.py (most nodes should have this)
        if not (node_path / '__init__.py').exists():
            # Some nodes might not have __init__.py, check for .py files
            py_files = list(node_path.glob('*.py'))
            if not py_files:
                logger.warning(f"No Python files found in {node_path.name}")
                return False

        return True

    def export_node_list(self, output_file: Path) -> bool:
        """Export the list of installed nodes to a JSON file."""
        try:
            nodes = self.list_installed_nodes()
            with open(output_file, 'w') as f:
                json.dump(nodes, f, indent=2)
            logger.info(f"Exported node list to: {output_file}")
            return True
        except Exception as e:
            logger.error(f"Error exporting node list: {e}")
            return False

    def import_node_list(self, input_file: Path) -> bool:
        """Import and install nodes from a JSON file."""
        try:
            with open(input_file, 'r') as f:
                nodes = json.load(f)

            success = True
            for node in nodes:
                if 'url' in node:
                    if not self.install_node(
                        node['url'],
                        branch=node.get('branch'),
                        commit=node.get('commit')
                    ):
                        success = False

            return success

        except Exception as e:
            logger.error(f"Error importing node list: {e}")
            return False