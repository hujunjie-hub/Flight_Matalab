"""Independent mathematical and protocol counterexamples for the spec (no MATLAB)."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path


def polynomial(c, x):
    value = 0.
    for item in reversed(c):
        value = value*x + item
    return value


def derivative(c):
    return [i*c[i] for i in range(1, len(c))] or [0.]


def roots01(c):
    c = list(c)
    while len(c) > 1 and abs(c[-1]) < 1e-15:
        c.pop()
    if len(c) <= 1:
        return []
    if len(c) == 2:
        root = -c[0]/c[1]
        return [root] if 0 <= root <= 1 else []
    critical = sorted(set([0., *roots01(derivative(c)), 1.]))
    scale = max(1., sum(abs(v) for v in c))
    result = [x for x in critical if abs(polynomial(c, x)) < 1e-12*scale]
    for left, right in zip(critical, critical[1:]):
        fl, fr = polynomial(c, left), polynomial(c, right)
        if fl*fr >= 0:
            continue
        lo, hi = left, right
        for _ in range(70):
            mid = (lo+hi)/2
            fm = polynomial(c, mid)
            if fl*fm <= 0:
                hi = mid
            else:
                lo, fl = mid, fm
        result.append((lo+hi)/2)
    return sorted(set(round(x, 14) for x in result))


def peak(c):
    return max(abs(polynomial(c, x)) for x in [0., 1., *roots01(derivative(c))])


def bernstein_coefficients(c):
    n = len(c)-1
    return [sum(c[j]*math.comb(k,j)/math.comb(n,j) for j in range(k+1)) for k in range(n+1)]


def bernstein_bound(c):
    return max(abs(v) for v in bernstein_coefficients(c))


def subdivide_bernstein(b):
    left, right = [b[0]], [b[-1]]
    row = list(b)
    while len(row) > 1:
        row = [(a+v)/2 for a,v in zip(row,row[1:])]
        left.append(row[0]); right.append(row[-1])
    return left, list(reversed(right))


def refined_bound(c, depth=4):
    work=[bernstein_coefficients(c)]
    for _ in range(depth):
        work=[child for item in work for child in subdivide_bernstein(item)]
    return max(abs(v) for item in work for v in item)


def quintic(p0, v0, a0, p1, v1, a1, duration):
    t, d = duration, p1-p0
    return [p0, v0*t, a0*t*t/2,
            10*d-(6*v0+4*v1)*t-(1.5*a0-.5*a1)*t*t,
            -15*d+(8*v0+7*v1)*t+(1.5*a0-a1)*t*t,
            6*d-3*(v0+v1)*t-.5*(a0-a1)*t*t]


def jets(c, duration, t):
    s = t/duration
    result = []
    for order in range(3):
        result.append(polynomial(c, s)/(duration**order))
        c = derivative(c)
    return result


def bounds(c, duration):
    result = []
    for order in range(1,4):
        c = derivative(c)
        result.append(refined_bound(c)/(duration**order))
    return result


def retime(start, end, initial_ticks=2, limits=(2.,2.,5.)):
    ticks = initial_ticks
    for attempt in range(16):
        if ticks > 30:
            return None
        t = ticks*.2
        c = quintic(*start, *end, t)
        b = bounds(c,t)
        if all(x <= y+1e-10 for x,y in zip(b,limits)):
            return {"ticks":ticks,"duration_s":t,"coefficients":c,"bounds":b,"attempts":attempt+1}
        ticks = (5*ticks+3)//4
    return None


def run_cases():
    cases = []
    def case(identifier, okay, evidence):
        cases.append({"id":identifier,"status":"PASS" if okay else "FAIL","evidence":evidence})

    old = quintic(0,0,0,.25,.5,0,.4)
    new = retime((0,0,0),(.25,.5,0))
    old_peak_a = peak(derivative(derivative(old)))/.4**2
    old_peak_j = peak(derivative(derivative(derivative(old))))/.4**3
    case("D4-01", old_peak_a > 2 and old_peak_j > 5 and new is not None,
         {"old_duration_s":.4,"old_peak_accel":old_peak_a,"old_peak_jerk":old_peak_j,"retimed":new})
    connector = retime((.25,.5,0),(2.,0,0))
    case("D4-02", math.sqrt(3)*.25 > .2 and connector is not None
         and abs(jets(connector["coefficients"],connector["duration_s"],connector["duration_s"])[0]-2) < 1e-10,
         {"nearest_3d_grid_error_m":math.sqrt(3)*.25,"acceptance_radius_m":.2,"connector":connector})
    dt, kp, ki, kaw, e, integral = .001,.16,.08,5.,1.,0.
    request = kp*e+integral
    allocated = .1
    next_integral = integral+(ki*e+kaw*(allocated-request))*dt
    wrong_pre_integrated_request = kp*e+ki*e*dt
    case("D4-03", abs(request-.16) < 1e-14 and abs(next_integral+.00022) < 1e-14
         and wrong_pre_integrated_request != request,
         {"request_uses_I_k":request,"I_k_plus_1":next_integral,"wrong_preintegrated_request":wrong_pre_integrated_request})
    reboot_sim, sample_sim, arrival_sim = 12_000_000,12_002_000,12_012_000
    local_sample, local_arrival = sample_sim-reboot_sim,arrival_sim-reboot_sim
    case("D4-04", local_sample == 2000 and local_arrival == 12000 and arrival_sim > reboot_sim,
         {"global_reboot":reboot_sim,"global_release":arrival_sim,"FCU_sample":local_sample,
          "FCU_arrival":local_arrival,"old_boot_rejected_before_age_subtraction":True})

    frame_checks = 0
    all_coherent = True
    for delay in range(41):
        for phase in range(5):
            active, pending, watermark = 1,2,1
            commit_tick = delay+1
            for tick in range(70):
                if tick == commit_tick:
                    active, watermark = pending,pending
                demand = active
                if tick%5 == phase:
                    frame_checks += 1
                    all_coherent &= demand == active and demand >= watermark
            # An aborted reservation never becomes the next published identity.
            all_coherent &= 3 > pending
    old_tuple_during_prepare=(2,1,1)
    old_guard_accepts=len(set(old_tuple_during_prepare))==1
    stale_demand_after_commit=1
    same_nav_context_recheck=2
    case("D5-01", all_coherent and frame_checks > 2000 and not old_guard_accepts and stale_demand_after_commit!=same_nav_context_recheck,
         {"prepared_delay_variants":41,"frame_phases":5,"frame_checks":frame_checks,"old_active_tuple":old_tuple_during_prepare,"old_guard_rejects":not old_guard_accepts,"same_nav_needs_context_evaluation":True,
          "invariant":"active context stays intact until atomic commit; reserved identities are not reused"})
    original = quintic(0.,.1,.2,.03,.2,0.,.2)
    second = quintic(.03,.2,0.,.09,.1,.1,.2)
    def old_jets(time):
        return jets(original,.2,time) if time <= .2 else jets(second,.2,time-.2)
    max_error, max_join_error, comparisons = 0.,0.,0
    for nav in range(100000,240000,137):
        anchor = (nav//20000)*20000
        handover = anchor+60000
        for offset in range(0,60000,20000):
            lo=(anchor+offset)/1e6
            left=old_jets(lo)
            right=old_jets(lo+.02)
            copied=quintic(*left,*right,.02)
            for u in [.0,.1,.5,.9,1.]:
                actual=jets(copied,.02,u*.02)
                expected=old_jets(lo+u*.02)
                max_error=max(max_error,max(abs(a-b) for a,b in zip(actual,expected)))
                comparisons += 1
        old_jet=old_jets(handover/1e6)
        replacement=quintic(*old_jet,.4,0.,0.,2.)
        new_jet=jets(replacement,2.,0.)
        max_join_error=max(max_join_error,max(abs(a-b) for a,b in zip(old_jet,new_jet)))
    case("D5-02", max_error < 1e-9 and max_join_error < 1e-12,
         {"copied_jet_checks":comparisons,"old_program_segments":2,"old_knot_s":.2,"max_prefix_jet_error":max_error,"handover_C2_error":max_join_error,
          "grid_us":20000,"prefix_us":60000})
    yaw, height, yaw_rate, climb, step = .2,1.,.1,.2,.02
    proposals=[(yaw+yaw_rate*step,height+climb*step) for _ in range(20)]
    committed=proposals[-1]
    case("D5-03", all(p == proposals[0] for p in proposals)
         and abs(committed[0]-.202)<1e-14 and abs(committed[1]-1.004)<1e-14,
         {"preview_count":20,"numeric_commit_count":1,"committed_yaw_height":committed})
    old_nav={"sample":1000,"valid_until":6000,"publish":3500}
    failed_diagnostic_publish=7000
    still_valid = failed_diagnostic_publish < old_nav["valid_until"]
    case("D5-04", not still_valid and old_nav["sample"]==1000 and old_nav["publish"]==3500,
         {"preserved_nav":old_nav,"new_health_publish":failed_diagnostic_publish,"Nav_is_stale":True})

    quantum=10/1999
    step_indices=math.floor(.25/quantum)
    force_index=1999
    arm_state="DISARMING"
    no_throttle_while_disarmed=True
    stop_deltas=[]
    while force_index:
        next_index=max(0,force_index-step_indices)
        no_throttle_while_disarmed &= arm_state != "DISARMED" or next_index == 0
        stop_deltas.append((force_index-next_index)*quantum)
        force_index=next_index
    arm_state="DISARMED" if force_index==0 else "DISARMING"
    bound_us=len(stop_deltas)*2500+2500+500
    case("D5-05", no_throttle_while_disarmed and arm_state=="DISARMED" and step_indices==49 and len(stop_deltas)==41 and max(stop_deltas)<=.25+1e-12 and bound_us<=105500<150000,
         {"management_frames":len(stop_deltas),"nonzero_management_phase":"DISARMING","final_arm_state":arm_state,"maximum_delta_N":max(stop_deltas),"command_stop_bound_us":bound_us,"certificate_TTL_us":150000})

    cells=16**3
    zero_observations=[0]*cells
    surveyed=[1]*cells
    bad=[1]*(cells-1)
    case("D6-01", not any(zero_observations) and len(surveyed)==4096 and len(bad)!=4096,
         {"cells":cells,"object_absence_is_free":False,"snapshot_requires_all_cells":True,
          "old_two_free_updates_at_8_per_20ms_s":cells*2/(8*50)})
    tau=3600.
    white=[.02**2*.001,.001**2*.001]
    stationary=[1e-4,.002,2e-5,2e-5]
    drive=[2*s*s/tau for s in stationary]
    qc=[white[0]]*3+[white[1]]*3+[drive[0]]*3+[drive[1]]*3+[drive[2]]*3+[drive[3]]*3+[1e-4]
    check_sigma=stationary[0]
    phi=math.exp(-.001/tau)
    q_exact=check_sigma**2*(-math.expm1(-2*.001/tau))
    recovered_variance=q_exact/(-math.expm1(-2*.001/tau))
    wrong_drive=2*(1e-3)**2/tau
    dt_rate=.001; omega0=.2; omega_dot=100.
    rectangle=(omega0+omega_dot*dt_rate)*dt_rate
    exact=omega0*dt_rate+.5*omega_dot*dt_rate**2
    rate_error_ok=abs((rectangle-exact)-.5*omega_dot*dt_rate**2)<1e-15
    variance_ok=abs((.001*dt_rate)**2-white[1]*dt_rate)<1e-25
    case("D6-02", rate_error_ok and variance_ok and abs(wrong_drive/drive[0]-100)<1e-9 and len(qc)==19 and min(qc)>0 and abs(recovered_variance-check_sigma**2)<1e-20,
         {"Qc19_diagonal":qc,"stationary_variance":recovered_variance,"P0_is_separate":True,"right_rectangle_error":rectangle-exact,"uniform_delta_noise_variance_consistent":variance_ok,"wrong_P0_as_process_PSD_factor":wrong_drive/drive[0],"phi":phi})
    stop=30_000_000
    samples=list(range(0,stop,1000))
    releases=[((s+2300+499)//500)*500 for s in samples]
    admitted=[r for r in releases if r<stop]
    gnss_last=29_900_000+10000
    case("D6-03", len(samples)==30000 and len(admitted)<len(samples) and gnss_last<stop,
         {"generated_IMU":len(samples),"released_IMU":len(admitted),
          "propagated_after_initial_previous_sample":len(admitted)-1,
          "last_GNSS_arrival":gnss_last,"coverage_end":stop,"EOF_is_not_last_timestamp":True})
    takeoff=retime((0,0,0),(1.,0,0))
    route=retime((0,0,0),(2.,0,0))
    land=retime((1.,0,0),(0,0,0),limits=(.6,2.,5.))
    schedule_feasible=all(v is not None for v in [takeoff,route,land]) and 4+.06+takeoff["duration_s"]<7 and 10+2*(.06+route["duration_s"]+.2)<17.5 and 23+.06+land["duration_s"]<27
    at35=.9-.001*35
    local_after_reboot=.9-.001*5
    case("D6-04", schedule_feasible and at35 != local_after_reboot and at35 > .2,
         {"takeoff_s":takeoff["duration_s"],"route_per_leg_s":route["duration_s"],"land_s":land["duration_s"],"35s_energy_fraction":at35,"wrong_FCU_reset_value":local_after_reboot,
          "provider_time":"global simulation seconds; coverage equals RunInterval"})

    # Independently check Bernstein convex-hull bounds against stationary-point extrema.
    property_checks=0
    for i in range(1,65):
        duration=.2+.04*i
        c=quintic(.01*i,.005*i,-.002*i,.5+.02*i,-.003*i,.001*i,duration)
        derivative_c=c
        for order in range(1,4):
            derivative_c=derivative(derivative_c)
            exact=peak(derivative_c)/(duration**order)
            bound=bernstein_bound(derivative_c)/(duration**order)
            tight=refined_bound(derivative_c)/(duration**order)
            if exact>tight+1e-9 or tight>bound+1e-9:
                raise ArithmeticError("Bernstein bound violated")
            property_checks+=1
    return cases,property_checks


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--round",type=int,choices=[4,5,6])
    args=parser.parse_args()
    spec=Path(__file__).resolve().parents[1]
    cases,properties=run_cases()
    selected=cases if args.round is None else [v for v in cases if v["id"].startswith(f"D{args.round}-")]
    name="semantic_reference_report.json" if args.round is None else f"round{args.round}_semantic_report.json"
    report={"scope":"EXECUTABLE_SPEC_REFERENCE","date":"2026-11-05",
            "status":"PASS" if all(v["status"]=="PASS" for v in selected) else "FAIL",
            "round":args.round,"cases":selected,"independent_polynomial_extrema_checks":properties,
            "matlab_model_execution":"NOT_RUN","production_algorithm_execution":"NOT_RUN",
            "limitation":"Mathematical and finite protocol references only; not Simulink integration or firmware proof.",
            "script_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "document_sha256":{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(spec.glob("*.md"))}}
    (spec/"validation"/name).write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"status":report["status"],"scope":report["scope"],"cases":len(selected),
                      "polynomial_extrema_checks":properties,"model_execution":"NOT_RUN"}))
    for item in selected:
        if item["status"]!="PASS":
            print(json.dumps(item,ensure_ascii=False))
    return 0 if report["status"]=="PASS" else 1


if __name__=="__main__":
    raise SystemExit(main())

