#!/usr/bin/env python3
"""Archive the MIT Recipe Registry Forever database without installing code.

The normal MobAuction integration reads an installed RecipeRegistry_Forever
addon. This utility is for reproducible database research: it resolves main to
one commit (or accepts --commit), downloads only metadata and its license, and
records their source URLs and SHA-256 hashes. It never executes downloaded Lua.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import tempfile
import urllib.error
import urllib.request


REPOSITORY = "colettamattia91-cloud/Recipe-Registry"
DATA_PATH = "RecipeRegistry_Forever/Data/Metadata/RecipeMetadata_Generated.lua"
MAX_BYTES = 16 * 1024 * 1024


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "MobAuction-reference-research"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError("Download exceeds the expected reference-file size")
    return data


def inspect_metadata(data):
    text = data.decode("utf-8")
    if not re.search(r"^RecipeRegistryRecipeMetadata\s*=\s*\{", text, re.MULTILINE):
        raise ValueError("Expected RecipeRegistryRecipeMetadata table is absent")
    schema = re.search(r"\bschemaVersion\s*=\s*(\d+)", text)
    flavor = re.search(r'\bflavor\s*=\s*"([^"]+)"', text)
    version = re.search(r'\bmetadataVersion\s*=\s*"([^"]+)"', text)
    records = re.search(r"\brecipesBySpellId\s*=\s*\{(.*?)\n    \},", text, re.DOTALL)
    if not schema or schema.group(1) != "1" or not flavor or flavor.group(1) != "forever":
        raise ValueError("Only the inspected Forever schema version 1 is supported")
    if not version or not records:
        raise ValueError("Metadata version or recipe table is absent")
    body = records.group(1)
    ids = re.findall(r"^        \[(\d+)\] = \{", body, re.MULTILINE)
    if not ids or len(set(ids)) != len(ids):
        raise ValueError("Recipe records are empty or contain duplicate spell IDs")
    professions = sorted(set(re.findall(r'\bprofession = "([^"]+)"', body)))
    return {
        "schemaVersion": 1,
        "flavor": "forever",
        "metadataVersion": version.group(1),
        "recipeCount": len(ids),
        "professions": professions,
        "recipeItemMappings": len(re.findall(r"\brecipeItemId\s*=\s*\d+", body)),
        "removedRecords": len(re.findall(r"\bremoved\s*=\s*true", body)),
        "validation": "Text structure only; recipe facts and learnability require current game verification",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", help="40-character Git commit; omitted resolves main once before downloading")
    parser.add_argument("--output", type=Path, help="New archive directory; default tools/registry-reference/<commit>")
    args = parser.parse_args()
    try:
        commit = args.commit
        if commit is None:
            commit = json.loads(fetch(f"https://api.github.com/repos/{REPOSITORY}/commits/main"))["sha"]
        if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", commit):
            raise ValueError("Commit must be a full 40-character hexadecimal Git ID")
        commit = commit.lower()
        destination = args.output or Path("tools/registry-reference") / commit
        if destination.exists():
            raise ValueError(f"Archive directory already exists: {destination}")
        base = f"https://raw.githubusercontent.com/{REPOSITORY}/{commit}"
        urls = {"RecipeMetadata_Generated.lua": f"{base}/{DATA_PATH}", "LICENSE": f"{base}/LICENSE"}
        payloads = {name: fetch(url) for name, url in urls.items()}
        license_text = payloads["LICENSE"].decode("utf-8")
        if "MIT License" not in license_text or "Permission is hereby granted" not in license_text:
            raise ValueError("Expected MIT license was not found; archive was not written")
        metadata = inspect_metadata(payloads["RecipeMetadata_Generated.lua"])
        provenance = {
            "repository": f"https://github.com/{REPOSITORY}",
            "commit": commit,
            "files": {name: {"url": urls[name], "sha256": hashlib.sha256(data).hexdigest()}
                      for name, data in payloads.items()},
            "metadata": metadata,
            "purpose": "Reference archive only; not installed or loaded by MobAuction",
        }
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".registry-download-", dir=destination.parent) as temporary:
            staged = Path(temporary) / "archive"
            staged.mkdir()
            for name, data in payloads.items():
                (staged / name).write_bytes(data)
            (staged / "PROVENANCE.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
            if destination.exists():
                raise ValueError(f"Archive directory appeared during download: {destination}")
            staged.rename(destination)
        print(f"Archived {metadata['recipeCount']} reference records from commit {commit} in {destination}")
        print("The archive is not installed. Use RecipeRegistry_Forever for the optional in-game database integration.")
    except (OSError, ValueError, KeyError, urllib.error.URLError) as error:
        parser.exit(1, f"Reference download failed: {error}\n")


if __name__ == "__main__":
    main()
