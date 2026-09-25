/*
 * Golden-vector tests for BlazeBinary C.
 * Usage: test_blaze_binary <path to Fixtures/golden/primitives.txt>
 *
 * For every "ok" vector: C encode == golden bytes, C decode(golden) == value,
 * and encoding into a buffer one byte too small fails without writing.
 * For every "err"/"strict" vector: C decode fails with the right class and
 * leaves the reader offset untouched.
 */

#include "blaze_binary.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
static int checks = 0;

#define CHECK(cond, ...)                                  \
    do {                                                  \
        checks++;                                         \
        if (!(cond)) {                                    \
            failures++;                                   \
            fprintf(stderr, "FAIL line %d: ", line_no);   \
            fprintf(stderr, __VA_ARGS__);                 \
            fprintf(stderr, "\n");                        \
        }                                                 \
    } while (0)

static size_t parse_hex(const char *hex, uint8_t *out, size_t cap) {
    if (strcmp(hex, "-") == 0) return 0;
    size_t n = strlen(hex) / 2;
    if (n > cap) n = cap;
    for (size_t i = 0; i < n; i++) {
        unsigned b;
        sscanf(hex + 2 * i, "%2x", &b);
        out[i] = (uint8_t)b;
    }
    return n;
}

static void to_hex(const uint8_t *b, size_t n, char *out) {
    for (size_t i = 0; i < n; i++) snprintf(out + 2 * i, 3, "%02x", b[i]);
    out[2 * n] = '\0';
}

/* Encode `value` of `type` with C. Returns result; sets *len. */
static blaze_binary_result_t c_encode(const char *type, const char *value, uint8_t *buf, size_t cap, size_t *len) {
    blaze_binary_writer_t w;
    blaze_binary_writer_init(&w, buf, cap);
    blaze_binary_result_t res;
    if (strcmp(type, "u8") == 0) res = blaze_binary_write_u8(&w, (uint8_t)strtoull(value, NULL, 10));
    else if (strcmp(type, "u16") == 0) res = blaze_binary_write_u16(&w, (uint16_t)strtoull(value, NULL, 10));
    else if (strcmp(type, "u32") == 0) res = blaze_binary_write_u32(&w, (uint32_t)strtoull(value, NULL, 10));
    else if (strcmp(type, "u64") == 0) res = blaze_binary_write_u64(&w, strtoull(value, NULL, 10));
    else if (strcmp(type, "int") == 0) res = blaze_binary_write_int(&w, strtoll(value, NULL, 10));
    else if (strcmp(type, "bool") == 0) res = blaze_binary_write_bool(&w, strcmp(value, "1") == 0);
    else if (strcmp(type, "schema") == 0) {
        unsigned version, payload;
        sscanf(value, "%u:%u", &version, &payload);
        res = blaze_binary_write_schema_version(&w, (uint8_t)version);
        if (res == BLAZE_BINARY_OK) res = blaze_binary_write_u8(&w, (uint8_t)payload);
    } else res = BLAZE_BINARY_INVALID;
    *len = w.offset;
    return res;
}

/* Decode one value of `type` with C into a canonical string. */
static blaze_binary_result_t c_decode(const char *type, const uint8_t *buf, size_t n, char *out, size_t *consumed) {
    blaze_binary_reader_t r;
    blaze_binary_reader_init(&r, buf, n);
    blaze_binary_result_t res;
    if (strcmp(type, "u8") == 0) {
        uint8_t v = 0; res = blaze_binary_read_u8(&r, &v); snprintf(out, 64, "%u", v);
    } else if (strcmp(type, "u16") == 0) {
        uint16_t v = 0; res = blaze_binary_read_u16(&r, &v); snprintf(out, 64, "%u", v);
    } else if (strcmp(type, "u32") == 0) {
        uint32_t v = 0; res = blaze_binary_read_u32(&r, &v); snprintf(out, 64, "%" PRIu32, v);
    } else if (strcmp(type, "u64") == 0) {
        uint64_t v = 0; res = blaze_binary_read_u64(&r, &v); snprintf(out, 64, "%" PRIu64, v);
    } else if (strcmp(type, "int") == 0) {
        int64_t v = 0; res = blaze_binary_read_int(&r, &v); snprintf(out, 64, "%" PRId64, v);
    } else if (strcmp(type, "bool") == 0) {
        bool v = false; res = blaze_binary_read_bool(&r, &v); snprintf(out, 64, "%d", v ? 1 : 0);
    } else if (strcmp(type, "schema") == 0) {
        uint8_t version = 0, payload = 0;
        res = blaze_binary_read_schema_version(&r, &version);
        if (res == BLAZE_BINARY_OK) res = blaze_binary_read_u8(&r, &payload);
        snprintf(out, 64, "%u:%u", version, payload);
    } else res = BLAZE_BINARY_INVALID;
    *consumed = r.offset;
    return res;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <primitives.txt>\n", argv[0]);
        return 2;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror(argv[1]);
        return 2;
    }

    char line[512];
    int line_no = 0, ok_vectors = 0, err_vectors = 0, strict_vectors = 0;
    while (fgets(line, sizeof line, f)) {
        line_no++;
        char kind[16], type[16], a[128], b[128];
        if (line[0] == '#' || line[0] == '\n') continue;
        int fields = sscanf(line, "%15s %15s %127s %127s", kind, type, a, b);

        uint8_t golden[64], buf[64];
        char hex[160], decoded[64];
        size_t len = 0, consumed = 0;

        if (strcmp(kind, "ok") == 0 && fields == 4) {
            ok_vectors++;
            size_t glen = parse_hex(b, golden, sizeof golden);

            blaze_binary_result_t res = c_encode(type, a, buf, sizeof buf, &len);
            to_hex(buf, len, hex);
            CHECK(res == BLAZE_BINARY_OK && len == glen && memcmp(buf, golden, glen) == 0,
                  "encode %s %s: got %s want %s", type, a, hex, b);

            res = c_decode(type, golden, glen, decoded, &consumed);
            CHECK(res == BLAZE_BINARY_OK && strcmp(decoded, a) == 0 && consumed == glen,
                  "decode %s %s: got %s (res %d, consumed %zu)", type, b, decoded, res, consumed);

            /* One byte short: must fail and write nothing past capacity. */
            memset(buf, 0xAA, sizeof buf);
            res = c_encode(type, a, buf, glen - 1, &len);
            CHECK(res == BLAZE_BINARY_BUFFER_TOO_SMALL && buf[glen - 1] == 0xAA,
                  "short buffer %s %s: res %d", type, a, res);
        } else if ((strcmp(kind, "err") == 0 && fields == 4) || (strcmp(kind, "strict") == 0 && fields == 3)) {
            bool strict = strcmp(kind, "strict") == 0;
            if (strict) strict_vectors++; else err_vectors++;
            size_t glen = parse_hex(a, golden, sizeof golden);
            blaze_binary_result_t res = c_decode(type, golden, glen, decoded, &consumed);
            bool want_truncated = !strict && strcmp(b, "truncated") == 0;
            bool ok_class = want_truncated ? (res == BLAZE_BINARY_EOF)
                                           : (res == BLAZE_BINARY_INVALID || res == BLAZE_BINARY_OVERFLOW);
            CHECK(ok_class && consumed == 0, "%s %s %s: res %d consumed %zu", kind, type, a, res, consumed);
        } else {
            fprintf(stderr, "bad fixture line %d\n", line_no);
            failures++;
        }
    }
    fclose(f);

    /* Schema writer rejects out-of-range versions and non-empty writers. */
    {
        uint8_t buf[8];
        blaze_binary_writer_t w;
        line_no = 0;
        blaze_binary_writer_init(&w, buf, sizeof buf);
        CHECK(blaze_binary_write_schema_version(&w, 0) == BLAZE_BINARY_UNSUPPORTED_VERSION, "schema 0");
        CHECK(blaze_binary_write_schema_version(&w, 128) == BLAZE_BINARY_UNSUPPORTED_VERSION, "schema 128");
        CHECK(blaze_binary_write_schema_version(&w, 1) == BLAZE_BINARY_OK && w.offset == 0, "schema 1 writes nothing");
        blaze_binary_write_u8(&w, 1);
        CHECK(blaze_binary_write_schema_version(&w, 2) == BLAZE_BINARY_INVALID, "schema after data");

        /* Marker needs > 2 bytes total, same as Swift: FE 02 alone is v1 data. */
        const uint8_t two[] = {0xFE, 0x02};
        blaze_binary_reader_t r;
        uint8_t version = 0;
        blaze_binary_reader_init(&r, two, 2);
        CHECK(blaze_binary_read_schema_version(&r, &version) == BLAZE_BINARY_OK && version == 1 && r.offset == 0,
              "FE 02 alone is v1");
        const uint8_t high[] = {0xFE, 0x80, 0x01};
        blaze_binary_reader_init(&r, high, 3);
        CHECK(blaze_binary_read_schema_version(&r, &version) == BLAZE_BINARY_OK && version == 1 && r.offset == 0,
              "FE 80 is not a marker");
    }

    printf("BlazeBinary C golden tests: %d ok vectors, %d err vectors, %d strict vectors, %d checks, %d failures\n",
           ok_vectors, err_vectors, strict_vectors, checks, failures);
    return failures == 0 ? 0 : 1;
}
