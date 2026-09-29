---
name: version-manager
description: Manages semantic versioning, Git tags, and changelog updates for the project.
---

# Version Manager Skill

## Goal
Automate version increments and maintain a consistent changelog based on project changes.

## Execution Steps
1. **Analyze recent changes**: Review git commits since the last tag using `git log`.
2. **Determine version bump**:
   - **PATCH** (1.0.X): For bug fixes.
   - **MINOR** (1.X.0): For new, backward-compatible features.
   - **MAJOR** (X.0.0): For breaking changes or incompatible API changes.
3. **Update configuration files**: Modify the version number in key files (e.g., `package.json`, `version.txt`, `pyproject.toml`).
4. **Generate Changelog**: Append a dated entry to `CHANGELOG.md` detailing the changes.
5. **Create Git Tag**: Execute commands to commit changes, create a new tag (`git tag vX.Y.Z`), and prepare it for pushing.
