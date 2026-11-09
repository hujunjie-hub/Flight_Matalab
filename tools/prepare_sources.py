"""Lock read-only inputs before creating any functional FlightSIM model."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FLIGHT = ROOT.parent / 'Flight'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    for folder in ('simulation', 'models/core', 'models/plant', 'models/lib',
                   'interfaces', 'dictionaries', 'config/SIM_ONLY/QUAD_X4',
                   'scenarios', 'tests', 'adapters/kf_gins_matlab',
                   'third_party_notices', 'work/mex', 'work/validation',
                   'work/dependencies', 'work/gates'):
        (ROOT / folder).mkdir(parents=True, exist_ok=True)
    sources=json.loads((ROOT / 'config/firmware_sources.json').read_text())
    headers = list((ROOT / sources['contracts_dir']).rglob('*.h'))
    headers = [p.resolve() for p in headers]
    osqp = (ROOT / sources['osqp_dir']).resolve()
    lock = json.loads((osqp / 'UPSTREAM_LOCK.json').read_text())
    assert (lock['version'], lock['mode'], lock['variables'], lock['constraints']) == ('1.0.0', 2, 15, 190)
    mismatches = [name for name, digest in lock['files'].items()
                  if sha(osqp / 'generated' / name) != digest]
    assert not mismatches, f'OSQP source hash mismatch: {mismatches}'
    archive = FLIGHT / 'build/dependency_cache/osqp-v1.0.0.tar.gz'
    source_lock = json.loads((osqp / 'SOURCE_LOCK.json').read_text())
    inventory = json.loads((ROOT / 'spec/validation/source_inventory.json').read_text())
    kf_commit = inventory['kf_gins_matlab']['commit']
    kf = ROOT / 'work/dependencies/KF-GINS-Matlab'
    if not kf.exists():
        subprocess.run(['git', 'clone', '--filter=blob:none', '--no-checkout',
                        'https://github.com/i2Nav-WHU/KF-GINS-Matlab.git', str(kf)], check=True)
        subprocess.run(['git', '-C', str(kf), 'checkout', '--detach', kf_commit], check=True)
    actual = subprocess.check_output(['git', '-C', str(kf), 'rev-parse', 'HEAD'], text=True).strip()
    assert actual == kf_commit, f'KF commit mismatch: {actual}'
    for name, digest in inventory['kf_gins_matlab']['files_sha256'].items():
        assert sha(kf / name) == digest, f'KF input mismatch: {name}'
    report = {
        'scope': 'G0_SOURCE_DEPENDENCIES', 'status': 'PASS',
        'implementation': sources['implementation'], 'firmware_equivalent': False,
        'headers': {p.relative_to(FLIGHT).as_posix(): sha(p) for p in sorted(headers)},
        'osqp': {'root': sources['osqp_dir'], 'source_lock': source_lock,
                 'runtime_lock_sha256': sha(osqp / 'UPSTREAM_LOCK.json'),
                 'verified_files': len(lock['files']), 'archive_sha256': sha(archive)},
        'kf_gins_matlab': {'path': 'work/dependencies/KF-GINS-Matlab',
                           'commit': actual,
                           'files': {str(p.relative_to(kf)).replace('\\', '/'): sha(p)
                                     for p in sorted(kf.rglob('*'))
                                     if p.is_file() and '.git' not in p.parts}},
        'model_compile': 'NOT_RUN', 'simulation': 'NOT_RUN', 'code_generation': 'NOT_RUN'
    }
    target = ROOT / 'external_dependencies.lock.json'
    if target.exists():
        previous = json.loads(target.read_text(encoding='utf-8'))
        if previous.get('implementation') != sources['implementation']:
            history = ROOT / 'config/dependency_history'
            history.mkdir(exist_ok=True)
            (history / (sha(target) + '.json')).write_bytes(target.read_bytes())
        else:
            assert previous == report, 'Existing dependency lock differs; review the input change before replacing the lock.'
    target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    (ROOT / 'third_party_notices/KF-GINS-Matlab-LICENSE.txt').write_bytes((kf / 'LICENSE').read_bytes())
    (ROOT / 'third_party_notices/OSQP-LICENSE.txt').write_bytes((osqp / 'LICENSE').read_bytes())
    print(json.dumps({'status': 'PASS', 'osqp_verified_files': len(lock['files']),
                      'kf_commit': actual, 'dependency_lock': str(target)}))


if __name__ == '__main__':
    main()

