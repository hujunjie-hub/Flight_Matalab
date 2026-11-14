#include "mex.h"
#include "systime.h"
#include "unicore_ascii/unicore_ascii.h"

#include <stdio.h>
#include <string.h>

#define PROBE_TICK_HZ 10000000u
#define EXPECTED_UTC_NS UINT64_C(1700000000000000000)
#define EXPECTED_GPS_NS UINT64_C(1384035218000000000)

static unsigned checks;
static unsigned failures;
static uint64_t raw_tick;
static uint32_t raw_epoch = 1u;

#define CHECK(condition) do { \
    ++checks; \
    if (!(condition)) { \
        ++failures; \
        mexPrintf("RECTIME probe FAIL at line %d: %s\n", __LINE__, #condition); \
    } \
} while (0)

static Status probe_tick_source(uint64_t *tick64, uint32_t *time_epoch)
{
    if (tick64 == NULL || time_epoch == NULL) return STATUS_INVALID_ARGUMENT;
    *tick64 = raw_tick;
    *time_epoch = raw_epoch;
    return STATUS_OK;
}

static uint32_t probe_crc32(const char *data, size_t length)
{
    uint32_t crc = 0u;
    unsigned bit;
    while (length-- != 0u) {
        crc ^= (uint8_t)*data++;
        for (bit = 0u; bit < 8u; ++bit) {
            crc = (crc >> 1) ^ ((crc & 1u) ? 0xedb88320u : 0u);
        }
    }
    return crc;
}

static int build_rectime_frame(char *frame, size_t capacity, int utc_offset_seconds)
{
    char body[256];
    int length;
    uint32_t crc;

    /* 2023-11-14 22:13:20 UTC; GPS week 2288, TOW 252818 s.
     * GPS-UTC separation is 18 s. Output delay is deliberately nonzero. */
    length = snprintf(body, sizeof(body),
        "#RECTIMEA,COM1,GPS,FINE,2288,252818000,18,0,0,12;"
        "VALID,0,0.00000,%d,2023,11,14,22,13,20000,VALID",
        utc_offset_seconds);
    if (length <= 0 || (size_t)length >= sizeof(body)) return 0;
    crc = probe_crc32(body + 1, (size_t)length - 1u);
    length = snprintf(frame, capacity, "%s*%08X\r\n", body, crc);
    return length > 0 && (size_t)length < capacity;
}

static int feed_frame(UnicoreAsciiParser *parser, const char *frame,
                      UnicoreAsciiMessage *message)
{
    size_t i;
    int result = 0;
    for (i = 0u; frame[i] != '\0'; ++i) {
        const int decoded = unicore_ascii_feed(parser, (uint8_t)frame[i], message);
        if (decoded != 0) result = decoded;
    }
    return result;
}

static int run_rectime_tests(uint32_t *mapping_epoch, uint8_t *utc_valid)
{
    char valid_frame[384];
    char bad_crc_frame[384];
    char bad_epoch_frame[384];
    UnicoreAsciiParser parser = {0};
    UnicoreAsciiMessage message = {0};
    UnicoreAsciiMessage valid_message = {0};
    int decoded;
    TimeConfig config = {0};
    PpsCaptureEvent edge;
    PpsCaptureEvent latest;
    GnssTimeObservation observation;
    GnssTimeObservation bad_pair;
    TimeServiceStatus status;
    ClockDomainMappingStatus mapping;
    unsigned i;
    Status init_status;

    CHECK(build_rectime_frame(valid_frame, sizeof(valid_frame), -18));
    if (failures != 0u) return 0;

    decoded = feed_frame(&parser, valid_frame, &message);
    CHECK(decoded == 1);
    CHECK(message.kind == UNICORE_ASCII_RECTIME);
    CHECK(message.utc_time_ns == EXPECTED_UTC_NS);
    CHECK(message.gps_time_ns == EXPECTED_GPS_NS);
    CHECK(message.receiver_accuracy_ns == 1000u);
    CHECK(message.output_delay_ms == 12u);
    CHECK(parser.valid_frames == 1u && parser.crc_errors == 0u &&
          parser.malformed_frames == 0u);
    valid_message = message;

    CHECK(build_rectime_frame(bad_crc_frame, sizeof(bad_crc_frame), -18));
    {
        char *star = strchr(bad_crc_frame, '*');
        CHECK(star != NULL);
        if (star != NULL) star[1] = (star[1] == '0') ? '1' : '0';
    }
    memset(&parser, 0, sizeof(parser));
    decoded = feed_frame(&parser, bad_crc_frame, &message);
    CHECK(decoded == -2 && parser.crc_errors == 1u);

    CHECK(build_rectime_frame(bad_epoch_frame, sizeof(bad_epoch_frame), -17));
    memset(&parser, 0, sizeof(parser));
    decoded = feed_frame(&parser, bad_epoch_frame, &message);
    CHECK(decoded == -1 && parser.malformed_frames == 1u);

    config.boot_id = 0x52454354u;
    config.time_epoch = 1u;
    config.tick_hz = PROBE_TICK_HZ;
    config.gnss_pps_installed = 1u;
    config.holdover_rate_bound_ppb = 10000u;
    raw_tick = 0u;
    raw_epoch = 1u;
    init_status = systime_init(&config, probe_tick_source);
    CHECK(init_status == STATUS_OK);
    if (init_status != STATUS_OK) return 0;

    for (i = 1u; i <= 9u; ++i) {
        raw_tick = (uint64_t)i * PROBE_TICK_HZ;
        memset(&edge, 0, sizeof(edge));
        edge.capture_tick64 = raw_tick;
        edge.edge_sequence = i;
        edge.time_epoch = 1u;
        edge.capture_flags = TIMER_CAPTURE_VALID;
        CHECK(time_submit_pps(&edge) == STATUS_OK);
    }

    memset(&latest, 0, sizeof(latest));
    CHECK(time_get_latest_pps(&latest) == STATUS_OK);
    CHECK(latest.capture_tick64 == 9ull * PROBE_TICK_HZ);
    CHECK(latest.edge_sequence == 9u);

    memset(&observation, 0, sizeof(observation));
    observation.utc_time_ns = valid_message.utc_time_ns;
    observation.paired_pps_tick64 = latest.capture_tick64;
    observation.pps_edge_sequence = latest.edge_sequence;
    observation.time_epoch = latest.time_epoch;
    observation.receiver_accuracy_ns = valid_message.receiver_accuracy_ns;
    observation.time_scale = TIME_SCALE_UTC;
    observation.validity_flags = GNSS_TIME_UTC_VALID | GNSS_TIME_PPS_PAIRED;
    CHECK(time_submit_gnss_time(&observation) == STATUS_OK);

    raw_tick = latest.capture_tick64;
    memset(&status, 0, sizeof(status));
    CHECK(time_get_status(&status) == STATUS_OK);
    CHECK(status.utc_valid != 0u);
    CHECK(status.state == TIME_QUALITY_LOCKED);
    CHECK(status.utc_estimate_ns == EXPECTED_UTC_NS);
    CHECK(status.utc_uncertainty_ns <= valid_message.receiver_accuracy_ns);

    memset(&mapping, 0, sizeof(mapping));
    CHECK(time_get_mapping_status(CLOCK_DOMAIN_UTC_POSIX, &mapping) == STATUS_OK);
    CHECK(mapping.mapping_state == CLOCK_MAPPING_LOCKED);
    CHECK(mapping.mapping_epoch != 0u);
    CHECK(mapping.anchor_source_time_ns == EXPECTED_UTC_NS);

    bad_pair = observation;
    bad_pair.paired_pps_tick64 -= PROBE_TICK_HZ;
    bad_pair.pps_edge_sequence -= 1u;
    CHECK(time_submit_gnss_time(&bad_pair) == STATUS_STALE_DATA);
    memset(&mapping, 0, sizeof(mapping));
    CHECK(time_get_mapping_status(CLOCK_DOMAIN_UTC_POSIX, &mapping) == STATUS_OK);
    CHECK(mapping.mapping_state == CLOCK_MAPPING_LOCKED);

    *mapping_epoch = mapping.mapping_epoch;
    *utc_valid = status.utc_valid;
    CHECK(systime_stop() == STATUS_OK);
    return 1;
}

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    const char *fields[] = {"status", "checks", "failures", "suite",
                            "utc_mapping_epoch", "utc_valid"};
    mxArray *result;
    uint32_t mapping_epoch = 0u;
    uint8_t utc_valid = 0u;
    int ran;

    (void)prhs;
    if (nrhs != 0 || nlhs > 1) {
        mexErrMsgIdAndTxt("Flight:RectimeProbeArguments",
            "fmt_rectime_time_probe accepts no inputs and returns at most one output.");
    }

    checks = 0u;
    failures = 0u;
    ran = run_rectime_tests(&mapping_epoch, &utc_valid);

    if (nlhs == 0) return;
    result = mxCreateStructMatrix(1, 1, 6, fields);
    mxSetField(result, 0, "status", mxCreateDoubleScalar((ran && failures == 0u) ? 0.0 : 1.0));
    mxSetField(result, 0, "checks", mxCreateDoubleScalar((double)checks));
    mxSetField(result, 0, "failures", mxCreateDoubleScalar((double)failures));
    mxSetField(result, 0, "suite", mxCreateString("Flight unicore_ascii RECTIMEA + systime.c"));
    mxSetField(result, 0, "utc_mapping_epoch", mxCreateDoubleScalar((double)mapping_epoch));
    mxSetField(result, 0, "utc_valid", mxCreateDoubleScalar((double)utc_valid));
    plhs[0] = result;
}
