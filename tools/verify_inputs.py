"""Fail closed on changed locked inputs and invalid SIM_ONLY configuration."""
from pathlib import Path
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'Duplicate configuration field: {key}')
        result[key] = value
    return result


def read(path):
    def invalid(value):
        raise ValueError(f'Nonfinite JSON constant: {value}')
    return json.loads(path.read_text(encoding='utf-8-sig'), object_pairs_hook=unique_object,
                      parse_constant=invalid)


def finite(value):
    if isinstance(value, dict):
        for item in value.values():
            finite(item)
    elif isinstance(value, list):
        for item in value:
            finite(item)
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        assert math.isfinite(value), 'Nonfinite parameter'


def matrix3(flat):
    assert len(flat) == 9, 'Inertia must contain nine elements'
    return [flat[0:3], flat[3:6], flat[6:9]]


def determinant3(m):
    return (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
            - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))


def main():
    report_path = ROOT / 'work/validation/input_preflight.json'
    report = {'scope': 'LOCKED_INPUT_PREFLIGHT', 'status': 'IN_PROGRESS'}
    try:
        lock = read(ROOT / 'external_dependencies.lock.json')
        flight = ROOT.parent / 'Flight'
        for name, digest in lock['headers'].items():
            assert sha(flight / name) == digest, f'Production header changed: {name}'
        baseline = read(ROOT / 'config/flight_baseline.json')
        for name, digest in baseline['sources_sha256'].items():
            assert sha(flight / name) == digest, f'Flight baseline changed: {name}'
        osqp = (ROOT / lock['osqp']['root']).resolve()
        assert sha(osqp / 'UPSTREAM_LOCK.json') == lock['osqp']['runtime_lock_sha256'], 'OSQP runtime lock changed'
        runtime = read(osqp / 'UPSTREAM_LOCK.json')
        for name, digest in runtime['files'].items():
            assert sha(osqp / 'generated' / name) == digest, f'OSQP runtime changed: {name}'
        kf = ROOT / lock['kf_gins_matlab']['path']
        for name, digest in lock['kf_gins_matlab']['files'].items():
            assert sha(kf / name) == digest, f'KF-GINS reference changed: {name}'

        hashes = {}
        config = {}
        for file in sorted((ROOT / 'config/SIM_ONLY/QUAD_X4').iterdir()):
            if file.suffix in {'.json', '.yaml'}:
                value = read(file)
                finite(value)
                assert value['status'] == 'SIM_ONLY', f'Missing synthetic source tag: {file.name}'
                config[file.stem] = value
                hashes[str(file.relative_to(ROOT)).replace(chr(92), '/')] = sha(file)
        assert set(config) == {'vehicle_model', 'sensor_alignment', 'estimator_tuning',
                               'controller_tuning', 'profile_manifest'}, 'Expected four COREs and readonly Profile'

        profile = config['profile_manifest']
        for flag in ('gnss_installed', 'gnss_enabled', 'pps_installed', 'pps_enabled'):
            assert profile.get(flag) is True, f'Fixed device flag must be true: {flag}'
        assert profile['implementation'] == 'HOST_NATIVE_V2' and profile['firmware_equivalent'] is False
        assert profile['base_step_us'] == 500
        force_curve = profile['dshot_force_curve_n']
        assert len(force_curve) == 2 and 0 <= force_curve[0] < force_curve[1]
        assert profile['frame_slew_nps'] * profile['frame_period_ticks'] * .0005 >= force_curve[1] / 1999

        # SIM_ONLY owns only plant-specific effects; Flight owns vehicle mass,
        # inertia, motor geometry, thrust limits and motor time constants.
        plant = config['vehicle_model']
        assert plant['motor_thrust_coefficient_n_s2'] > 0
        assert len(plant['drag_ned_kgps']) == 3 and all(x >= 0 for x in plant['drag_ned_kgps'])
        assert plant['rate_damping_nm_s'] >= 0
        assert plant['ground_stiffness_npm'] > 0 and plant['ground_damping_ns_pm'] >= 0
        assert len(plant['contact_lever_frd_m']) == 3
        assert len(plant['skid_half_span_m']) == 2 and all(x >= 0 for x in plant['skid_half_span_m'])
        assert len(plant['plant_state0']) == 17

        flight_vehicle = read(flight / 'config/vehicle_model.yaml')
        assert flight_vehicle['profile'] == 'QUAD_X4' and flight_vehicle['status'] == 'SIM_ONLY'
        assert flight_vehicle['mass_kg'] > 0
        inertia = matrix3(flight_vehicle['inertia_frd_kgm2'])
        scale = max(1.0, *(abs(value) for row in inertia for value in row))
        tolerance = 1e-10 * scale
        assert abs(inertia[0][1] - inertia[1][0]) <= tolerance
        assert abs(inertia[0][2] - inertia[2][0]) <= tolerance
        assert abs(inertia[1][2] - inertia[2][1]) <= tolerance
        assert inertia[0][0] > 0
        assert inertia[0][0] * inertia[1][1] - inertia[0][1] ** 2 > 0
        assert determinant3(inertia) > 0

        positions = flight_vehicle['motor_position_frd_m']
        assert len(positions) == 4 and all(len(position) == 3 for position in positions)
        assert len(flight_vehicle['motor_yaw_torque_ratio_m']) == 4
        motor_min = flight_vehicle['motor_min_thrust_n']
        motor_max = flight_vehicle['motor_max_thrust_n']
        assert len(motor_min) == 4 and len(motor_max) == 4
        assert all(0 <= lo < hi for lo, hi in zip(motor_min, motor_max))
        motor_tau = flight_vehicle['motor_time_constant_s']
        assert len(motor_tau) == 4 and all(math.isfinite(x) and x > 0 for x in motor_tau)
        assert max(motor_tau) - min(motor_tau) < 1e-12

        estimator = config['estimator_tuning']
        assert (estimator['error_state_rank'], estimator['noise_rank']) == (22, 19)
        assert estimator['bias_correlation_time_s'] > 0
        report.update(status='PASS', headers_verified=len(lock['headers']),
                      osqp_files_verified=len(runtime['files']),
                      kf_files_verified=len(lock['kf_gins_matlab']['files']),
                      flight_vehicle_fields_verified=7,
                      plant_parameter_contract='FULL_3X3_INERTIA_25',
                      frame_quantizer_max_thrust_n=force_curve[1],
                      config_hashes=hashes,
                      config_content_sha256=hashlib.sha256(json.dumps(config, sort_keys=True, separators=(',', ':')).encode()).hexdigest())
    except Exception as error:
        report.update(status='FAIL', error=str(error))
        raise
    finally:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'config_hashes'}))


if __name__ == '__main__':
    main()
