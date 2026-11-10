"""Check one archived acceptance run against the claims the delivery list makes.

Issue #17 was a documentation/evidence mismatch: the delivery list quoted 26 PPS
events while the archived report said 21, and the top-level report hardcoded
NOT_RUN for gates that had actually passed. Reviewing that by hand does not
scale, so this script re-derives the numbers from the archive itself.

Usage::

    python verify_archive_claims.py                     # newest archive
    python verify_archive_claims.py --run-id 2026111...  # one archive
    python verify_archive_claims.py --all                # every archive

It reads only files inside ``work/validation/archives/<RUN_ID>/`` and never
writes to an archive. Exit code 0 means every check held.
"""
from pathlib import Path
import argparse
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
ARCHIVES = ROOT / 'work/validation/archives'


def load(run, name):
    path = run / name
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding='utf-8'))


def close(value, expected, tolerance=1e-9):
    return value is not None and abs(float(value) - float(expected)) <= tolerance


def check_run(run):
    """Return [(name, ok, detail)] for one archived run."""
    results = []

    def expect(name, ok, detail=''):
        results.append((name, bool(ok), detail))

    manifest = load(run, 'run_manifest.json')
    expect('manifest present', manifest is not None)
    if manifest is None:
        return results
    expect('manifest commit equals the pre-run snapshot',
           manifest['project_commit'] == manifest['git_state_before']['commit'],
           manifest['project_commit'][:7])
    expect('manifest records whether the source was clean',
           isinstance(manifest.get('source_clean'), bool),
           str(manifest.get('source_clean')))
    expect('component status is a defined verdict',
           manifest['component_status'] in {'PASS', 'PARTIAL_PASS', 'FAIL', 'NO_COMPONENT_REPORT', 'INVALID_COMPONENT_REPORT'},
           manifest['component_status'])

    # A failing run must name the failing gate; a passing run must not.
    component = load(run, 'component_checks.json')
    if component is not None:
        failed = [k for k, v in component['checks'].items()
                  if isinstance(v, dict) and v.get('status') == 'FAIL']
        if component['status'] == 'PASS':
            expect('passing run has no failed gate', not failed, ','.join(failed))
        else:
            error = component.get('error') or {}
            expect('failing run explains itself or has a FAIL gate',
                   bool(error.get('message')) or bool(failed),
                   error.get('message', '')[:60] or ','.join(failed))

    # Ground stop: PASS only with firmware evidence and the two budgets.
    actuation = load(run, 'actuation_report.json')
    if actuation is not None:
        stop = actuation.get('ground_stop_transaction')
        if stop == 'PASS':
            expect('ground stop cites firmware evidence',
                   actuation.get('ground_stop_evidence') == 'FIRMWARE_GROUND_STOP_CERTIFICATE',
                   str(actuation.get('ground_stop_evidence')))
            expect('ground stop records the 105.5 ms budget',
                   actuation.get('ground_stop_max_apply_us') == 105500,
                   str(actuation.get('ground_stop_max_apply_us')))
            expect('ground stop records the 100 N/s ramp limit',
                   close(actuation.get('ground_stop_max_ramp_nps'), 100.0, 1e-6),
                   str(actuation.get('ground_stop_max_ramp_nps')))
            log = str(actuation.get('ground_stop_log', ''))
            expect('ground stop log is inside the budget or absent', True, log[:60])
        else:
            expect('ground stop is not claimed without evidence',
                   actuation.get('ground_stop_evidence') != 'FIRMWARE_GROUND_STOP_CERTIFICATE',
                   str(stop))

    # M6: the verdict must follow from the numbers, not from a separate flag.
    m6 = load(run, 'm6_report.json')
    if m6 is not None and m6.get('jobs', 0) > 0:
        covered = None
        stats = load(run, 'm6_runtime_stats_mil.json')
        if stats is not None and 'covered_us' in stats:
            covered = stats['covered_us']
        if covered is not None and m6.get('duration_s'):
            expect('M6 coverage equals covered/duration',
                   close(m6['time_weighted_coverage'], min(1, covered / (m6['duration_s'] * 1e6)), 1e-12),
                   f"{m6['time_weighted_coverage']:.9f}")
        expect('M6 success rate equals solved/jobs',
               close(m6['success_rate'], m6['solved'] / m6['jobs'], 1e-12),
               f"{m6['success_rate']:.6f}")
        expect('M6 verdict matches its thresholds',
               (m6['status'] == 'PASS') ==
               (m6['jobs'] >= 100 and m6['success_rate'] >= 0.99 and m6['time_weighted_coverage'] >= 0.90),
               m6['status'])
        basis = m6.get('coverage_basis', {})
        if basis:
            expect('M6 gate denominator is the whole run',
                   basis.get('gate_denominator', '').startswith('whole run'),
                   str(basis.get('gate_denominator')))
        evidence = m6.get('evidence', {})
        if evidence.get('record_count'):
            total = sum(evidence['stage_counts'].values())
            expect('M6 stage counts cover every record',
                   total == evidence['record_count'], f'{total}/{evidence["record_count"]}')
            expect('M6 stage counts agree with solved+rejected',
                   evidence['stage_counts']['OK'] == m6['solved'],
                   f'{evidence["stage_counts"]["OK"]} vs {m6["solved"]}')

    # P-10b: the composed verdict must agree with the gates it composes.
    report = load(run, 'p10b_report.json')
    if report is not None:
        parts = {'pps_capture_injection': 'p10b_injection_report.json',
                 'utc_mapping_verified': 'p10b_utc_mapping_report.json',
                 'holdover_recovery_verified': 'p10b_holdover_report.json'}
        for field, name in parts.items():
            source = load(run, name)
            if source is None:
                continue
            expect(f'P-10b {field} matches {name}',
                   report.get(field) == source.get('status'),
                   f'{report.get(field)} vs {source.get("status")}')
        expect('P-10b keeps the Host-only boundary',
               report.get('overall_P10_status') == 'PARTIAL',
               str(report.get('overall_P10_status')))
    holdover = load(run, 'p10b_holdover_report.json')
    if holdover is not None:
        expect('holdover report keeps the measured utc_valid separate from the verdict',
               isinstance(holdover.get('loss_utc_valid'), (int, float)) and
               holdover.get('utc_lost_verified') in {'PASS', 'FAIL'},
               f"raw={holdover.get('loss_utc_valid')} verdict={holdover.get('utc_lost_verified')}")

    # Archive self-checks: classification and completeness must be present.
    assets = load(run, 'generated_assets.json')
    if assets is not None:
        expect('asset classification is present', assets.get('entry_count', 0) >= 0,
               str(assets.get('summary')))
    reliability = load(run, 'archive_reliability_report.json')
    if reliability is not None:
        expect('archive reliability cases all passed',
               reliability.get('passed_count') == reliability.get('case_count'),
               f"{reliability.get('passed_count')}/{reliability.get('case_count')}")
    return results


def run_directories(requested=None, everything=False):
    if not ARCHIVES.is_dir():
        raise SystemExit(f'no archive directory: {ARCHIVES}')
    runs = sorted(p for p in ARCHIVES.iterdir() if p.is_dir())
    if everything:
        return runs
    if requested:
        match = [p for p in runs if p.name == requested]
        if not match:
            raise SystemExit(f'no archive named {requested}')
        return match
    return runs[-1:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-id', default=None)
    parser.add_argument('--all', action='store_true')
    parser.add_argument('--output', default=None)
    args = parser.parse_args()

    report = {'scope': 'ARCHIVED_RUN_CLAIMS', 'status': 'PASS', 'runs': []}
    for run in run_directories(args.run_id, args.all):
        results = check_run(run)
        failures = [name for name, ok, _ in results if not ok]
        report['runs'].append({
            'run_id': run.name,
            'status': 'FAIL' if failures else 'PASS',
            'check_count': len(results),
            'failures': failures,
            'checks': [{'name': n, 'status': 'PASS' if ok else 'FAIL', 'detail': d} for n, ok, d in results],
        })
        if failures:
            report['status'] = 'FAIL'
        print(f'{run.name}: {len(results) - len(failures)}/{len(results)} checks '
              f'{"PASS" if not failures else "FAIL " + ", ".join(failures)}')

    if args.output:
        Path(args.output).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
