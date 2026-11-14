"""Record the repository state around an acceptance run.

The archive needs to prove *which* tree produced the evidence and whether the
operator ran against committed source or local edits.  Two snapshots of this
file are taken: one before ``run_component_checks`` touches anything and one
after it finishes, so regenerated models can be told apart from intended
source changes.
"""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def git(*arguments):
    result = subprocess.run(('git', '-C', str(ROOT)) + arguments,
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise SystemExit('git %s failed: %s' % (' '.join(arguments), result.stderr.strip()))
    return result.stdout.strip()


def status_entries():
    raw = subprocess.run(('git', '-C', str(ROOT), 'status', '--porcelain', '-z',
                          '--untracked-files=all'),
                         capture_output=True, text=True, check=False)
    if raw.returncode != 0:
        raise SystemExit('git status failed: %s' % raw.stderr.strip())
    entries = []
    for entry in raw.stdout.split('\0'):
        if len(entry) < 4:
            continue
        entries.append({
            'index': entry[0],
            'worktree': entry[1],
            'code': entry[:2].strip() or entry[:2],
            'path': entry[3:].replace('\\', '/'),
        })
    return entries


def snapshot(stage):
    entries = status_entries()
    return {
        'schema': 'flight-matalab-git-state/1.0',
        'stage': stage,
        'branch': git('rev-parse', '--abbrev-ref', 'HEAD'),
        'commit': git('rev-parse', 'HEAD'),
        'commit_subject': git('log', '-1', '--pretty=%s'),
        'captured_at_utc': subprocess.run(
            ('git', '-C', str(ROOT), 'log', '-1', '--pretty=%cI'),
            capture_output=True, text=True, check=False).stdout.strip(),
        'worktree_clean': not entries,
        'entry_count': len(entries),
        'entries': entries,
    }


if __name__ == '__main__':
    arguments = [a for a in sys.argv[1:] if not a.startswith('--root=')]
    root_option = [a for a in sys.argv[1:] if a.startswith('--root=')]
    if root_option:
        ROOT = Path(root_option[-1].split('=', 1)[1]).resolve()
    stage = arguments[0] if arguments else 'unknown'
    target = Path(arguments[1]) if len(arguments) > 1 else ROOT / ('work/validation/git_state_%s.json' % stage)
    target.parent.mkdir(parents=True, exist_ok=True)
    report = snapshot(stage)
    target.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({
        'stage': stage,
        'branch': report['branch'],
        'commit': report['commit'],
        'clean': report['worktree_clean'],
        'entries': report['entry_count'],
    }))
