"""
Model Manager for ComfyUI Builder
Handles downloading models from various sources including HuggingFace, CivitAI, and private repos.
"""

import hashlib
import json
import logging
import os
import re
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.parse import urlparse

import requests
from tqdm import tqdm

logger = logging.getLogger('model_manager')


class ModelManager:
    """Manages model downloads from multiple sources."""

    def __init__(self, base_dir: Path):
        self.base_dir = base_dir

        # Check for network volume (RunPod persistent storage)
        network_volume = Path('/runpod')
        if network_volume.exists() and network_volume.is_dir():
            # Use network volume for caching to persist across pod restarts
            self.cache_dir = network_volume / 'cache' / 'models'
            self.using_network_volume = True
            logger.info(f"Using network volume for model cache: {self.cache_dir}")
        else:
            # Fallback to local cache
            self.cache_dir = base_dir / '.cache' / 'models'
            self.using_network_volume = False
            logger.info(f"Using local cache: {self.cache_dir}")

        self.cache_dir.mkdir(parents=True, exist_ok=True)

        # Load environment variables
        self.hf_token = os.environ.get('HF_TOKEN', '')
        self.civitai_token = os.environ.get('CIVITAI_API_KEY', '')

    def download_collection(self, collection_config: Dict, output_dir: Optional[Path] = None) -> bool:
        """Download all models in a collection."""
        if output_dir is None:
            # Default to ComfyUI models directory
            output_dir = self.base_dir / 'ComfyUI' / 'models'

        logger.info(f"Downloading model collection: {collection_config.get('name', 'unnamed')}")

        models = collection_config.get('models', {})
        success = True

        for model_type, model_list in models.items():
            if not isinstance(model_list, list):
                continue

            type_dir = output_dir / model_type
            type_dir.mkdir(parents=True, exist_ok=True)

            for model in model_list:
                if not self._download_model(model, type_dir):
                    success = False
                    logger.error(f"Failed to download model: {model.get('name', 'unnamed')}")

        return success

    def _download_model(self, model_config: Dict, output_dir: Path) -> bool:
        """Download a single model based on its configuration."""
        url = model_config.get('url', '')
        name = model_config.get('name', '')
        filename = model_config.get('filename')

        if not url:
            logger.error(f"No URL specified for model: {name}")
            return False

        logger.info(f"Downloading model: {name}")

        # Determine download method based on URL format
        if url.startswith('civitai:'):
            return self._download_civitai(url[8:], name, output_dir, filename)
        elif url.startswith('fx1/collection/') or 'fx1/collection' in url:
            return self._download_private_hf(url, name, output_dir, filename)
        elif 'huggingface.co' in url or url.startswith('https://'):
            return self._download_direct(url, name, output_dir, filename)
        elif '/' in url and not url.startswith('http'):
            # Assume it's a HuggingFace model ID
            return self._download_huggingface(url, name, output_dir, filename)
        else:
            logger.error(f"Unknown URL format: {url}")
            return False

    def _download_direct(self, url: str, name: str, output_dir: Path, filename: Optional[str] = None) -> bool:
        """Download a file directly from a URL."""
        try:
            import shutil

            if filename is None:
                filename = name + self._get_extension_from_url(url)

            output_path = output_dir / filename

            # Check if already exists at destination
            if output_path.exists():
                logger.info(f"Model already exists: {output_path}")
                return True

            # Generate cache path based on URL hash for unique identification
            url_hash = hashlib.sha256(url.encode()).hexdigest()[:16]
            cache_filename = f"{url_hash}_{filename}"
            cache_path = self.cache_dir / cache_filename

            # Check if exists in cache
            if cache_path.exists() and cache_path.stat().st_size > 0:
                logger.info(f"Found model in cache, copying from: {cache_path}")
                try:
                    # Copy from cache to destination
                    shutil.copy2(cache_path, output_path)
                    logger.info(f"Successfully copied from cache: {filename}")
                    return True
                except Exception as e:
                    logger.warning(f"Failed to copy from cache: {e}, will download fresh")

            headers = {}
            if self.hf_token and 'huggingface.co' in url:
                headers['Authorization'] = f'Bearer {self.hf_token}'

            response = requests.get(url, headers=headers, stream=True, timeout=30)
            response.raise_for_status()

            total_size = int(response.headers.get('content-length', 0))

            # Download to cache first if using network volume
            download_path = cache_path if self.using_network_volume else output_path

            # Download with progress bar
            with open(download_path, 'wb') as f:
                with tqdm(total=total_size, unit='B', unit_scale=True, desc=filename) as pbar:
                    for chunk in response.iter_content(chunk_size=8192):
                        f.write(chunk)
                        pbar.update(len(chunk))

            # If we downloaded to cache, copy to final destination
            if self.using_network_volume and download_path != output_path:
                logger.info(f"Copying from cache to destination: {output_path}")
                shutil.copy2(download_path, output_path)

            logger.info(f"Successfully downloaded: {filename}")
            return True

        except Exception as e:
            logger.error(f"Error downloading {url}: {e}")
            if output_path.exists():
                output_path.unlink()
            return False

    def _download_huggingface(self, model_id: str, name: str, output_dir: Path, filename: Optional[str] = None) -> bool:
        """Download from HuggingFace model hub."""
        try:
            # Parse model ID
            parts = model_id.split('/')
            if len(parts) < 2:
                logger.error(f"Invalid HuggingFace model ID: {model_id}")
                return False

            # Extract repo and file path
            if len(parts) == 2:
                # Just repo ID, need to find main model file
                repo_id = model_id
                file_path = None
            else:
                repo_id = '/'.join(parts[:2])
                file_path = '/'.join(parts[2:])

            # Build HuggingFace URL
            if file_path:
                url = f"https://huggingface.co/{repo_id}/resolve/main/{file_path}"
            else:
                # Try common model file extensions
                for ext in ['.safetensors', '.ckpt', '.pt', '.pth', '.bin']:
                    test_url = f"https://huggingface.co/{repo_id}/resolve/main/model{ext}"
                    if self._check_url_exists(test_url):
                        url = test_url
                        if filename is None:
                            filename = name + ext
                        break
                else:
                    logger.error(f"Could not find model file in repo: {repo_id}")
                    return False

            return self._download_direct(url, name, output_dir, filename)

        except Exception as e:
            logger.error(f"Error downloading HuggingFace model {model_id}: {e}")
            return False

    def _download_private_hf(self, path: str, name: str, output_dir: Path, filename: Optional[str] = None) -> bool:
        """Download from private HuggingFace repository (fx1/collection)."""
        if not self.hf_token:
            logger.error("HF_TOKEN required for private repository access")
            return False

        try:
            # Clean up the path
            if path.startswith('fx1/collection/'):
                file_path = path[15:]  # Remove 'fx1/collection/' prefix
            elif 'fx1/collection' in path:
                # Extract file path after fx1/collection
                parts = path.split('fx1/collection')[-1].lstrip('/')
                file_path = parts
            else:
                file_path = path

            # Build URL for private repo
            url = f"https://huggingface.co/fx1/collection/resolve/main/{file_path}"

            if filename is None:
                filename = name + self._get_extension_from_url(file_path)

            return self._download_direct(url, name, output_dir, filename)

        except Exception as e:
            logger.error(f"Error downloading from private repo: {e}")
            return False

    def _download_civitai(self, model_id: str, name: str, output_dir: Path, filename: Optional[str] = None) -> bool:
        """Download from CivitAI."""
        try:
            # Get model info from CivitAI API
            api_url = f"https://civitai.com/api/v1/models/{model_id}"
            headers = {}
            if self.civitai_token:
                headers['Authorization'] = f'Bearer {self.civitai_token}'

            response = requests.get(api_url, headers=headers, timeout=30)
            response.raise_for_status()
            model_data = response.json()

            # Get the latest version
            if not model_data.get('modelVersions'):
                logger.error(f"No versions found for CivitAI model {model_id}")
                return False

            latest_version = model_data['modelVersions'][0]

            # Find the primary file
            files = latest_version.get('files', [])
            if not files:
                logger.error(f"No files found for CivitAI model {model_id}")
                return False

            # Get the primary/first file
            primary_file = None
            for f in files:
                if f.get('primary', False):
                    primary_file = f
                    break
            if primary_file is None:
                primary_file = files[0]

            download_url = primary_file.get('downloadUrl')
            if not download_url:
                logger.error(f"No download URL for CivitAI model {model_id}")
                return False

            if filename is None:
                filename = primary_file.get('name', f"{name}.safetensors")

            # Add CivitAI token to download URL if available
            if self.civitai_token:
                download_url += f"?token={self.civitai_token}"

            return self._download_direct(download_url, name, output_dir, filename)

        except Exception as e:
            logger.error(f"Error downloading CivitAI model {model_id}: {e}")
            return False

    def _check_url_exists(self, url: str) -> bool:
        """Check if a URL exists without downloading."""
        try:
            headers = {}
            if self.hf_token and 'huggingface.co' in url:
                headers['Authorization'] = f'Bearer {self.hf_token}'

            response = requests.head(url, headers=headers, timeout=10, allow_redirects=True)
            return response.status_code == 200
        except:
            return False

    def _get_extension_from_url(self, url: str) -> str:
        """Extract file extension from URL."""
        path = urlparse(url).path
        if '.' in path:
            return '.' + path.split('.')[-1]
        return '.safetensors'  # Default extension

    def verify_model(self, model_path: Path, expected_hash: Optional[str] = None) -> bool:
        """Verify a downloaded model using hash."""
        if not model_path.exists():
            return False

        if expected_hash is None:
            return True  # No hash to verify against

        try:
            sha256_hash = hashlib.sha256()
            with open(model_path, 'rb') as f:
                for chunk in iter(lambda: f.read(8192), b''):
                    sha256_hash.update(chunk)

            calculated_hash = sha256_hash.hexdigest()
            return calculated_hash.lower() == expected_hash.lower()

        except Exception as e:
            logger.error(f"Error verifying model {model_path}: {e}")
            return False

    def get_model_info(self, model_path: Path) -> Dict:
        """Get information about a model file."""
        if not model_path.exists():
            return {}

        info = {
            'name': model_path.name,
            'size': model_path.stat().st_size,
            'path': str(model_path),
        }

        # Try to get model type from path
        parent_dir = model_path.parent.name
        if parent_dir in ['checkpoints', 'loras', 'vae', 'controlnet', 'upscale_models']:
            info['type'] = parent_dir

        return info

    def list_downloaded_models(self, models_dir: Optional[Path] = None) -> Dict[str, List[Dict]]:
        """List all downloaded models organized by type."""
        if models_dir is None:
            models_dir = self.base_dir / 'models'

        models = {}
        model_types = ['checkpoints', 'loras', 'vae', 'controlnet', 'upscale_models']

        for model_type in model_types:
            type_dir = models_dir / model_type
            if type_dir.exists():
                models[model_type] = []
                for model_file in type_dir.glob('*'):
                    if model_file.is_file():
                        models[model_type].append(self.get_model_info(model_file))

        return models