"""Fingerprint the generated artifacts of a run and classify what it touched.

``fingerprint_sources.py`` deliberately ignores Simulink models, dictionaries,
MEX kernels and recordings because the build steps regenerate them.  Those files
still decide what actually executed, so they get their own digest here, plus a
classification that answers the question the manifest could not: *which of the
files a run dirtied are intended assets, which are throw-away build output, and
which are only auto-layout drift that ``git checkout`` can undo?*

Usage::

    python fingerprint_artifacts.py                       # before the run
    python fingerprint_artifacts.py --before before.json \
        --before-git git_state_before.json \
        --classification generated_assets.json            # after the run
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]

ARTIFACT_GROUPS = {
    'simulink_model': ('models/**/*.slx', 'simulation/**/*.slx', 'tests/**/*.slx', '*.slx'),
    'data_dictionary': ('dictionaries/**/*.sldd',),
    'mex_kernel': ('work/mex/**/*.mexw64', 'work/runtime/**/*.dll'),
    'recording': ('scenarios/*.mat', 'work/validation/*.mat'),
}

# Previous runs keep their own copies of the same artifacts; scanning them would
# make every fingerprint depend on the archive history instead of this run.
EXCLUDED_PREFIXES = ('work/validation/archives/', 'work/dependencies/', 'work/cache/')

SOURCE_DIRECTORIES = {'tools', 'models', 'simulation', 'interfaces', 'tests', 'config'}
SOURCE_SUFFIXES = {'.m', '.c', '.h', '.py', '.ps1', '.json', '.yaml', '.yml'}
TEMPORARY_SUFFIXES = {'.mexw64', '.dll', '.slxc', '.asv', '.autosave', '.obj', '.pdb'}
MODEL_SUFFIXES = {'.slx', '.mdl'}
DICTIONARY_SUFFIXES = {'.sldd'}


def classify_path(path):
    lowered = path.lower()
    name = Path(lowered).name
    suffix = Path(lowered).suffix
    if lowered.startswith('work/') or 'slprj/' in lowered or suffix in TEMPORARY_SUFFIXES:
        return 'temporary_build_artifact'
    if suffix in MODEL_SUFFIXES:
        return 'model_asset'
    if suffix in DICTIONARY_SUFFIXES:
        return 'dictionary_asset'
    if suffix == '.mat':
        return 'generated_input'
    if suffix in SOURCE_SUFFIXES and Path(lowered).parts[0] in SOURCE_DIRECTORIES:
        return 'source'
    if suffix in {'.md', '.txt'}:
        return 'documentation'
    if name.startswith('external_dependencies.lock'):
        return 'source'
    return 'other'


def disposition_for(entry_class, code, dirty_before, changed):
    if entry_class == 'temporary_build_artifact':
        return 'excluded_from_source'
    if entry_class in {'model_asset', 'dictionary_asset', 'generated_input'}:
        if code == '??':
            return 'commit_candidate'
        if dirty_before and not code:
            return 'restored_during_run'
        # A file that was already dirty may still be rewritten by this run.  The
        # old classifier reported both cases as pre_existing_local_change, so a
        # model or recording the run itself regenerated looked like an
        # untouchable user edit.  Compare the before/after digests to separate
        # them: only the untouched case is actually unattributable.
        if code and dirty_before:
            if changed:
                return 'pre_existing_local_change_modified_by_run'
            return 'pre_existing_local_change'
        if code and not dirty_before:
            return 'regenerated_by_run'
        if changed:
            return 'regenerated_by_run'
        return 'unchanged_asset'
    if entry_class == 'source':
        return 'uncommitted_source_change' if code else 'committed_source'
    if entry_class == 'documentation':
        return 'documentation_change' if code else 'committed_source'
    return 'unclassified'


def artifact_paths():
    paths = {}
    for group, patterns in ARTIFACT_GROUPS.items():
        for pattern in patterns:
            for path in ROOT.glob(pattern):
                if not path.is_file():
                    continue
                relative = str(path.relative_to(ROOT)).replace('\\', '/')
                if relative.startswith(EXCLUDED_PREFIXES):
                    continue
                paths.setdefault(relative, group)
    return paths


def hash_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def fingerprint():
    grouped = artifact_paths()
    files = {}
    groups = {}
    for relative, group in sorted(grouped.items()):
        files[relative] = hash_file(ROOT / relative)
        groups.setdefault(group, []).append(relative)
    payload = json.dumps(files, sort_keys=True, separators=(',', ':')).encode('utf-8')
    return {
        'schema': 'flight-matalab-artifact-fingerprint/1.0',
        'scope': {group: list(patterns) for group, patterns in ARTIFACT_GROUPS.items()},
        'sha256': hashlib.sha256(payload).hexdigest(),
        'file_count': len(files),
        'group_counts': {group: len(members) for group, members in groups.items()},
        'groups': {group: sorted(members) for group, members in groups.items()},
        'files': files,
    }


def git_status():
    raw = subprocess.run(('git', '-C', str(ROOT), 'status', '--porcelain', '-z',
                          '--untracked-files=all'),
                         capture_output=True, text=True, check=False)
    if raw.returncode != 0:
        raise SystemExit('git status failed: %s' % raw.stderr.strip())
    entries = {}
    for entry in raw.stdout.split('\0'):
        if len(entry) < 4:
            continue
        entries[entry[3:].replace('\\', '/')] = entry[:2].strip() or entry[:2]
    return entries


def classify(before_fingerprint, before_git):
    before_files = (before_fingerprint or {}).get('files', {})
    dirty_before = {entry['path'] for entry in (before_git or {}).get('entries', [])}
    after = fingerprint()
    after_files = after['files']
    status = git_status()

    entries = []
    for path in sorted(set(status) | set(before_files) | set(after_files)):
        code = status.get(path, '')
        entry_class = classify_path(path)
        changed = None
        if path in before_files or path in after_files:
            changed = before_files.get(path) != after_files.get(path)
        if not code and path not in dirty_before and not changed:
            continue
        entries.append({
            'path': path,
            'class': entry_class,
            'git_code': code or 'unchanged',
            'dirty_before_run': path in dirty_before,
            'changed_during_run': changed,
            'disposition': disposition_for(entry_class, code, path in dirty_before, changed),
            'sha256_before': before_files.get(path),
            'sha256_after': after_files.get(path),
        })

    summary = {}
    for entry in entries:
        summary[entry['disposition']] = summary.get(entry['disposition'], 0) + 1
    return after, {
        'schema': 'flight-matalab-generated-assets/1.0',
        'summary': summary,
        'entry_count': len(entries),
        'entries': entries,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', help='repository to scan (default: this checkout)')
    parser.add_argument('--output', default=None)
    parser.add_argument('--before')
    parser.add_argument('--before-git')
    parser.add_argument('--classification')
    arguments = parser.parse_args()
    if arguments.root:
        globals()['ROOT'] = Path(arguments.root).resolve()
    if not arguments.output:
        arguments.output = str(ROOT / 'work/validation/current_artifact_fingerprint.json')

    before = None
    if arguments.before:
        before = json.loads(Path(arguments.before).read_text(encoding='utf-8'))
    before_git = None
    if arguments.before_git:
        before_git = json.loads(Path(arguments.before_git).read_text(encoding='utf-8'))

    report, assets = classify(before, before_git)
    target = Path(arguments.output)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    if arguments.classification:
        Path(arguments.classification).write_text(json.dumps(assets, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({
        'sha256': report['sha256'],
        'file_count': report['file_count'],
        'group_counts': report['group_counts'],
        'summary': assets['summary'],
    }))


if __name__ == '__main__':
    main()
