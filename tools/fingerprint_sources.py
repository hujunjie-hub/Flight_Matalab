"""Hash the source inputs of a Flight_Matalab acceptance run.

Two digests are produced on purpose:

* ``committed_sha256`` covers the blobs recorded in ``git ls-tree HEAD`` for the
  in-scope source files.  It answers "which source was under test" and cannot be
  influenced by a working tree that a run just dirtied.
* ``sha256`` covers the same paths as they exist on disk.  It answers "what was
  actually loaded" and is therefore allowed to differ from the committed one
  when the operator runs with local edits; ``clean`` and ``dirty_files`` say so
  explicitly rather than letting regenerated results pass as committed source.

Generated material is deliberately out of scope: Simulink models (``.slx``),
data dictionaries (``.sldd``), compiled MEX kernels (``.mexw64``), recordings
(``.mat``) and everything under ``work/`` are produced by the build steps of the
run itself.  They are hashed separately by ``fingerprint_artifacts.py`` so that
regenerating a model can never change the source fingerprint.
"""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]

SOURCE_DIRECTORIES = ('tools', 'models', 'simulation', 'interfaces', 'tests', 'config')
SOURCE_SUFFIXES = {'.m', '.c', '.h', '.py', '.ps1', '.json', '.yaml', '.yml'}
EXCLUDED_TOP_LEVEL = {'work', 'archives', '.git'}
LOCK_FILE = 'external_dependencies.lock.json'

# Recorded here so the fingerprint report can state what it refused to hash.
GENERATED_SUFFIXES = {'.slx', '.sldd', '.mexw64', '.mat', '.mdl', '.slxc'}


def git(*arguments):
    result = subprocess.run(('git', '-C', str(ROOT)) + arguments,
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise SystemExit('git %s failed: %s' % (' '.join(arguments), result.stderr.strip()))
    return result.stdout


def in_scope(relative_path):
    path = Path(relative_path)
    if relative_path == LOCK_FILE:
        return True
    if path.suffix.lower() not in SOURCE_SUFFIXES:
        return False
    if path.parts and path.parts[0] in EXCLUDED_TOP_LEVEL:
        return False
    return path.parts[0] in SOURCE_DIRECTORIES


def worktree_status():
    """Ask git which in-scope paths differ from HEAD.

    git already applies the repository's line-ending and attribute filters, so
    this is the only trustworthy comparison on a Windows checkout with
    ``core.autocrlf`` enabled; hashing the raw bytes against the recorded blob
    would report every file as dirty.
    """
    result = subprocess.run(('git', '-C', str(ROOT), 'status', '--porcelain', '-z',
                             '--untracked-files=all'),
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise SystemExit('git status failed: %s' % result.stderr.strip())
    dirty, untracked = [], []
    for entry in result.stdout.split('\0'):
        if len(entry) < 4:
            continue
        code, path = entry[:2], entry[3:]
        if not in_scope(path):
            continue
        if code == '??':
            untracked.append(path)
        dirty.append(path)
    return dirty, untracked


def tracked_blobs():
    """Map every in-scope tracked path to the blob id recorded in HEAD."""
    blobs = {}
    for line in git('ls-tree', '-r', 'HEAD').splitlines():
        metadata, _, path = line.partition('\t')
        fields = metadata.split()
        if len(fields) < 3 or fields[1] != 'blob':
            continue
        if in_scope(path):
            blobs[path] = fields[2]
    return blobs


def worktree_files():
    files = {}
    for directory in SOURCE_DIRECTORIES:
        base = ROOT / directory
        if not base.is_dir():
            continue
        for path in sorted(base.rglob('*')):
            if not path.is_file():
                continue
            relative = str(path.relative_to(ROOT)).replace('\\', '/')
            if in_scope(relative):
                files[relative] = path
    lock = ROOT / LOCK_FILE
    if lock.is_file():
        files[LOCK_FILE] = lock
    return files


def digest(mapping):
    payload = json.dumps(mapping, sort_keys=True, separators=(',', ':')).encode('utf-8')
    return hashlib.sha256(payload).hexdigest()


def fingerprint():
    committed = tracked_blobs()
    worktree = worktree_files()
    dirty, untracked = worktree_status()

    disk_hashes = {}
    for relative, path in worktree.items():
        disk_hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()

    missing = sorted(set(committed) - set(worktree))

    return {
        'schema': 'flight-matalab-source-fingerprint/2.0',
        'scope': {
            'directories': list(SOURCE_DIRECTORIES),
            'suffixes': sorted(SOURCE_SUFFIXES),
            'lock_file': LOCK_FILE,
            'excluded_generated_suffixes': sorted(GENERATED_SUFFIXES),
        },
        'committed_sha256': digest({path: blob for path, blob in committed.items()}),
        'sha256': digest(disk_hashes),
        'file_count': len(disk_hashes),
        'committed_file_count': len(committed),
        'clean': not dirty and not missing,
        'dirty_files': sorted(dirty),
        'untracked_files': sorted(untracked),
        'missing_files': missing,
        'files': disk_hashes,
    }


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', help='repository to fingerprint (default: this checkout)')
    parser.add_argument('--output', help='report path (default: work/validation/current_source_fingerprint.json)')
    arguments = parser.parse_args()
    if arguments.root:
        ROOT = Path(arguments.root).resolve()
    target = Path(arguments.output) if arguments.output else ROOT / 'work/validation/current_source_fingerprint.json'
    result = fingerprint()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({
        'sha256': result['sha256'],
        'committed_sha256': result['committed_sha256'],
        'file_count': result['file_count'],
        'clean': result['clean'],
        'dirty_file_count': len(result['dirty_files']),
    }))
