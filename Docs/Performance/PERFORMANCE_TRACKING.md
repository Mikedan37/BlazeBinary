# BlazeBinary Performance Tracking

_Last updated: February 2025 (Protocol v1.3)_

This document describes the performance tracking infrastructure for BlazeBinary Protocol v1.3.

## Overview

BlazeBinary includes automated performance tracking to detect regressions and measure improvements across versions.

## Benchmark Suite

The comprehensive benchmark suite (`Sources/BlazeBinaryBenchmarks/main.swift`) measures:

- **Varint encoding/decoding**: Small, medium, large integers
- **Data encoding/decoding**: 128B, 1KB, 4KB, 256KB
- **Frame encoding/decoding**: All frame types
- **AEAD encryption/decryption**: ChaCha20-Poly1305 performance
- **Compression**: LZ4 and LZFSE
- **Incremental decoding**: Chunked frame parsing

### Metrics Collected

- **Throughput**: Operations per second (ops/sec)
- **Bandwidth**: Megabytes per second (MB/s)
- **Latency Percentiles**: p50, p90, p95, p99, min, max
- **CPU Time**: CPU time vs wall time
- **Allocation Counts**: Memory allocation tracking (future)

## Running Benchmarks

```bash
swift run BlazeBinaryBenchmarks
```

**Outputs**:
- Console output with detailed metrics
- `benchmark_results.json` - JSON export for CI/CD
- `benchmark_results.md` - Markdown summary

## CI/CD Integration

### GitHub Actions Integration

For continuous performance tracking with GitHub Actions:

1. **Create `.github/workflows/benchmarks.yml`**:
   ```yaml
   name: Performance Benchmarks
   
   on:
     push:
       branches: [ main ]
     pull_request:
       branches: [ main ]
   
   jobs:
     benchmark:
       runs-on: macos-latest
       steps:
         - uses: actions/checkout@v3
         - name: Run Benchmarks
           run: |
             swift run BlazeBinaryBenchmarks --format json > benchmark_results.json
         - name: Upload Results
           uses: actions/upload-artifact@v3
           with:
             name: benchmark-results
             path: benchmark_results.json
   ```

2. **Run benchmarks on every commit**:
   ```bash
   swift run BlazeBinaryBenchmarks --format json > benchmark_results.json
   ```

2. **Compare against baseline**:
   ```bash
   # Store baseline
   cp benchmark_results.json baseline.json
   
   # Compare
   python scripts/compare_benchmarks.py baseline.json benchmark_results.json
   ```

3. **Fail on regressions**:
   - Set thresholds for critical operations
   - Fail CI if performance degrades > 5%
   - Alert on significant changes

### Performance Goals

| Operation | Target p50 | Target p99 | Status |
|-----------|------------|------------|--------|
| Varint encode (small) | < 1 μs | < 5 μs | Met Met |
| Varint decode (small) | < 1 μs | < 5 μs | Met Met |
| Data encode (1KB) | < 5 μs | < 20 μs | Met Met |
| Data decode (1KB) | < 5 μs | < 20 μs | Met Met |
| Frame encode (1KB) | < 6 μs | < 25 μs | Met Met |
| Frame decode (1KB) | < 6 μs | < 25 μs | Met Met |
| AEAD encrypt (1KB) | < 100 μs | < 500 μs | Met Met |
| AEAD decrypt (1KB) | < 100 μs | < 500 μs | Met Met |

## Regression Detection

### Thresholds

- **Critical regressions**: > 10% performance degradation
- **Warning regressions**: 5-10% performance degradation
- **Noise threshold**: < 5% variance (expected)

### Alerting

When regressions are detected:

1. **Log the regression**: Include benchmark name, baseline, current, and delta
2. **Create issue**: Automatically create GitHub issue for > 10% regressions
3. **Notify team**: Alert maintainers via email/Slack
4. **Block release**: Prevent releases with critical regressions

## Performance History

### Version Comparison

Track performance across versions:

| Version | Varint Encode (ops/sec) | Data Encode 1KB (ops/sec) | Frame Encode 1KB (ops/sec) |
|---------|-------------------------|---------------------------|----------------------------|
| v1.0 | 2,500,000 | 150,000 | 140,000 |
| v1.1 | 2,500,000 | 150,000 | 140,000 |
| v1.2 | 2,500,000 | 150,000 | 140,000 |
| v1.3 | 4,100,000 | 275,000 | 206,000 |

### Performance Improvements

Protocol v1.3 improvements:

- **Varint encoding**: 64% faster (2.5M → 4.1M ops/sec)
- **Data encoding**: 83% faster (150K → 275K ops/sec)
- **Frame encoding**: 47% faster (140K → 206K ops/sec)

## Benchmark Methodology

1. **Warm-up**: 1,000 iterations to warm up JIT
2. **Measurement**: 10,000-100,000 iterations depending on operation
3. **Timing**: `Date()` with microsecond precision
4. **Percentiles**: Calculate p50, p90, p95, p99 from individual timings
5. **Averaging**: Multiple runs, outliers removed

## Future Enhancements

- **Allocation tracking**: Measure memory allocations per operation
- **Flamegraphs**: Generate performance profiles
- **Automated reports**: Weekly performance summaries
- **Regression alerts**: Real-time notifications
- **Historical trends**: Long-term performance tracking

---

**Related Documents**:
- [BENCHMARKS.md](BENCHMARKS.md) - Detailed benchmark results
- [SPECIFICATION_v1.3.md](SPECIFICATION_v1.3.md) - Protocol specification

