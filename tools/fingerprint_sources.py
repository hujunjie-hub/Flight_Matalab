"""Hash the actual model, code, dictionary, configuration and native binaries."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]


def fingerprint():
    files = {}
    for directory in ('tools', 'models', 'interfaces', 'tests', 'config', 'dictionaries', 'simulation', 'scenarios', 'work/mex'):
        for path in sorted((ROOT / directory).rglob('*')):
            if path.is_file() and path.suffix in {'.m', '.c', '.h', '.py', '.json', '.yaml', '.slx', '.sldd', '.mexw64', '.mat'}:
                files[str(path.relative_to(ROOT)).replace('\\', '/')] = hashlib.sha256(path.read_bytes()).hexdigest()
    lock = ROOT / 'external_dependencies.lock.json'
    files[lock.name] = hashlib.sha256(lock.read_bytes()).hexdigest()
    digest = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return {'sha256': digest, 'files': files, 'file_count': len(files)}


if __name__ == '__main__':
    result = fingerprint()
    target = ROOT / 'work/validation/current_source_fingerprint.json'
    target.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'sha256': result['sha256'], 'file_count': result['file_count']}))
