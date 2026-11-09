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
    assert len(flat) == 9, 'Inertia tensor must contain nine elements'
    return [flat[0:3], flat[3:6], flat[6:9]]


def validate_spd_inertia(flat):
    j = matrix3(flat)
    scale = max(1.0, *(abs(value) for row in j for value in row))
    tol = 1e-10 * scale
    assert max(abs(j[i][k] - j[k][i]) for i in range(3) for k in range(3)) <= tol, \
        'Inertia tensor must be symmetric'
    a, b, c = j[0]
    d, e, f = j[1]
    g, h, i = j[2]
    minor2 = a * e - b * d
    determinant = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    assert a > 0 and minor2 > 0 and determinant > 0, \
        'Inertia tensor must be positive definite'


def validate_rotation(flat, label):
    m = matrix3(flat)
    for row in range(3):
        for column in range(3):
            dot = sum(m[k][row] * m[k][column] for k in range(3))
            assert (abs(dot - (1.0 if row == column else 0.0)) <= 1e-6), f'{label} must be orthonormal'
    determinant = (
        m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
        - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
        + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
    )
    assert abs(determinant - 1.0) <= 1e-6, f'{label} must be a proper rotation'


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

        flight_vehicle = read(flight / 'config/vehicle_model.yaml')
        finite(flight_vehicle)
        assert flight_vehicle['profile'] == 'QUAD_X4' and flight_vehicle['status'] == 'SIM_ONLY'
        assert flight_vehicle['mass_kg'] > 0 and len(flight_vehicle['inertia_frd_kgm2']) == 9
        assert len(flight_vehicle['motor_position_frd_m']) == 4
        assert all(len(position) == 3 for position in flight_vehicle['motor_position_frd_m'])
        assert len(flight_vehicle['motor_yaw_torque_ratio_m']) == 4
        assert len(flight_vehicle['motor_min_thrust_n']) == 4
        assert len(flight_vehicle['motor_max_thrust_n']) == 4
        assert len(flight_vehicle['motor_time_constant_s']) == 4
        assert all(0 <= lo < hi for lo, hi in zip(
            flight_vehicle['motor_min_thrust_n'], flight_vehicle['motor_max_thrust_n']))
        assert all(tau > 0 for tau in flight_vehicle['motor_time_constant_s'])
        validate_spd_inertia(flight_vehicle['inertia_frd_kgm2'])
        positions = flight_vehicle['motor_position_frd_m']
        radii = [math.hypot(position[0], position[1]) for position in positions]
        assert max(radii) - min(radii) < 1e-10, 'X4 motor arms must have equal radial length'

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

        p = config['profile_manifest']
        for flag in ('gnss_installed', 'gnss_enabled', 'pps_installed', 'pps_enabled'):
            assert p.get(flag) is True, f'Fixed device flag must be true: {flag}'
        assert p['implementation'] == 'HOST_NATIVE_V2' and p['firmware_equivalent'] is False
        assert p['base_step_us'] == 500
        assert len(p['dshot_force_curve_n']) == 2 and p['dshot_force_curve_n'][1] > p['dshot_force_curve_n'][0]
        assert p['frame_slew_nps'] * p['frame_period_ticks'] * .0005 >= max(p['dshot_force_curve_n']) / 1999

        v = config['vehicle_model']
        assert v['motor_thrust_coefficient_n_s2'] > 0
        assert len(v['drag_ned_kgps']) == 3 and all(value >= 0 for value in v['drag_ned_kgps'])
        assert v['ground_stiffness_npm'] > 0 and v['ground_damping_ns_pm'] >= 0
        assert v['ground_friction'] == 0, 'First-version Plant must not enable unvalidated horizontal ground friction'
        assert len(v['plant_state0']) == 17
        assert math.sqrt(sum(value * value for value in v['plant_state0'][6:10])) > 1e-12
        assert all(value >= 0 for value in v['plant_state0'][13:17])
        assert len(v['origin_llh_rad_m']) == 3
        sensor = config['sensor_alignment']
        for field in ('magnetic_field_ned_ut', 'imu_to_cg_frd_m',
                      'antenna_from_imu_frd_m', 'static_gyro_bias_radps',
                      'static_accel_bias_mps2', 'scale_error',
                      'gyro_noise_std_radps', 'accel_noise_std_mps2',
                      'mag_noise_std_ut', 'gnss_position_noise_std_m',
                      'gnss_velocity_noise_std_mps'):
            assert len(sensor[field]) == 3, f'{field} must be a 3-vector'
            assert all(math.isfinite(float(value)) for value in sensor[field]), f'{field} must be finite'
        assert all(value > -1.0 for value in sensor['scale_error']), 'Scale error must preserve positive sensitivity'
        for field in ('gyro_noise_std_radps', 'accel_noise_std_mps2',
                      'mag_noise_std_ut', 'gnss_position_noise_std_m',
                      'gnss_velocity_noise_std_mps'):
            assert all(value >= 0.0 for value in sensor[field]), f'{field} cannot be negative'
        assert math.isfinite(sensor['baro_noise_std_m']) and sensor['baro_noise_std_m'] >= 0.0
        validate_rotation(sensor['imu_installation'], 'IMU installation')
        validate_rotation(sensor['mag_installation'], 'magnetometer installation')
        for field in ('imu_pipeline_delay_us', 'imu_transport_delay_us',
                      'gnss_transport_delay_us', 'baro_transport_delay_us',
                      'mag_transport_delay_us', 'imu_pipeline_uncertainty_us'):
            assert (isinstance(sensor[field], int) and not isinstance(sensor[field], bool)
                    and sensor[field] >= 0), f'{field} must be a nonnegative integer microsecond value'
        for field in ('imu_sample_period_us', 'mag_sample_period_us',
                      'baro_sample_period_us', 'gnss_sample_period_us'):
            assert (isinstance(sensor[field], int) and not isinstance(sensor[field], bool)
                    and sensor[field] >= 500 and sensor[field] % 500 == 0), \
                f'{field} must be a positive 500-us aligned sample period'
        assert (isinstance(sensor['random_seed'], int) and not isinstance(sensor['random_seed'], bool)
                and 0 < sensor['random_seed'] <= 0xffffffff), 'random_seed must be a nonzero uint32'
        assert sensor['gnss_backend'] == 'SIM_PVT'
        assert sensor['pps_backend'] == 'SIM_PPS_EPOCH'

        e = config['estimator_tuning']
        assert (e['error_state_rank'], e['noise_rank']) == (22, 19)
        assert e['bias_correlation_time_s'] > 0
        report.update(status='PASS', headers_verified=len(lock['headers']),
                      osqp_files_verified=len(runtime['files']),
                      kf_files_verified=len(lock['kf_gins_matlab']['files']),
                      flight_vehicle_source='Flight/config/vehicle_model.yaml',
                      plant_parameter_contract='FULL_3X3_INERTIA_26',
                      sensor_parameter_contract='SENSOR_19_IMU_ANTENNA_LEVERS',
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
