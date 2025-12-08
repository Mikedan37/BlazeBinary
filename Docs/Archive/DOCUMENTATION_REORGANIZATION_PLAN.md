# BlazeBinary Documentation Reorganization Plan

_Generated: February 2025_

## Classification Summary

**Total .md files**: 45  
**Files to keep**: 38  
**Files to move to Archive/**: 4  
**Files already in Archive/**: 13  
**New consolidation doc**: 1

---

## A) CORE DOCUMENTATION (Keep)

### Root Level:
- ✅ `README.md` - Main project documentation
- ✅ `RELEASE.md` - Release notes and process
- ✅ `CHANGELOG.md` - Version history
- ✅ `CONTRIBUTING.md` - Contribution guidelines
- ✅ `SECURITY.md` - Security policy (root level - standard GitHub location)
- ✅ `Issues.md` - Development issues tracking (standard at root)

### Docs/ (Core - v1.3 Production):
- ✅ `Docs/INDEX.md` - Documentation index
- ✅ `Docs/SPECIFICATION_v1.3.md` - **FROZEN** Protocol v1.3 specification
- ✅ `Docs/API_STABILITY.md` - API stability guarantees
- ✅ `Docs/VERSIONING.md` - Semantic versioning policy
- ✅ `Docs/FAILURE_SEMANTICS.md` - Failure modes and error handling
- ✅ `Docs/BENCHMARKS.md` - Performance benchmarks
- ✅ `Docs/FUZZING.md` - Fuzzing infrastructure
- ✅ `Docs/PERFORMANCE_TRACKING.md` - Performance tracking

### Docs/ (Core - General Reference):
- ✅ `Docs/SPECIFICATION.md` - General specification (evolving, not version-specific)
- ✅ `Docs/SECURITY.md` - Comprehensive security documentation (different from root SECURITY.md)

---

## B) DEVELOPER DOCS (Keep in Docs/)

- ✅ `Docs/ARCHITECTURE.md` - System architecture
- ✅ `Docs/ENCODING_MODEL.md` - Type system and encoding details
- ✅ `Docs/ENCRYPTION.md` - Secure Session Mode specification
- ✅ `Docs/FRAME_PROTOCOL.md` - Frame format and protocol
- ✅ `Docs/HANDSHAKE.md` - Handshake protocol specification
- ✅ `Docs/RATIONALE.md` - Design rationale and comparisons
- ✅ `Docs/ROADMAP.md` - Future work and enhancements
- ✅ `Docs/THREAT_MODEL.md` - Security threat model
- ✅ `Docs/SECURITY_REVIEW.md` - Comprehensive security review
- ✅ `Docs/CROSS_LANGUAGE_DECODER.md` - Cross-language implementation guide
- ✅ `Docs/HEXDUMP.md` - Hex dump utilities
- ✅ `Docs/ZERO_COPY_DECODING.md` - Zero-copy decoding API
- ✅ `Docs/ProtocolExamples.md` - Protocol usage examples
- ✅ `Docs/ProductionSafetyProfile.md` - Production safety guarantees
- ✅ `Docs/FaultToleranceChecklist.md` - Fault tolerance checklist

---

## D) LEGACY / AUDIT / OUTDATED DOCS (Move to Docs/Archive/)

### Root Level → Docs/Archive/:
1. 🔄 `PRODUCTION_READINESS_REPORT.md` → `Docs/Archive/PRODUCTION_READINESS_REPORT.md`
   - **Reason**: Internal audit report, not user-facing documentation

2. 🔄 `PROTOCOL_V1.2_IMPLEMENTATION_COMPLETE.md` → `Docs/Archive/PROTOCOL_V1.2_IMPLEMENTATION_COMPLETE.md`
   - **Reason**: Outdated protocol progress doc (v1.2, superseded by v1.3)

### Docs/ → Docs/Archive/:
3. 🔄 `Docs/PRODUCTION_READY.md` → `Docs/Archive/PRODUCTION_READY.md`
   - **Reason**: Internal audit verification checklist, superseded by PRODUCTION_READINESS_REPORT.md

### Already in Archive/ (No action needed):
- ✅ `Docs/Archive/AUDIT_COMPLETE_SUMMARY.md`
- ✅ `Docs/Archive/AUDIT_PROGRESS.md`
- ✅ `Docs/Archive/AUDIT_SUMMARY.md`
- ✅ `Docs/Archive/DOCS_ALIGNMENT_SUMMARY.md`
- ✅ `Docs/Archive/FINAL_RELEASE_AUDIT_SUMMARY.md`
- ✅ `Docs/Archive/FINAL_VERIFICATION_REPORT.md`
- ✅ `Docs/Archive/FULL_AUDIT_REPORT.md`
- ✅ `Docs/Archive/PATCH_VERIFICATION_REPORT.md`
- ✅ `Docs/Archive/PROTOCOL_MATURITY_AUDIT.md`
- ✅ `Docs/Archive/PROTOCOL_V1.1_PROGRESS.md`
- ✅ `Docs/Archive/PROTOCOL_V1.2_SUMMARY.md`
- ✅ `Docs/Archive/RELEASE_PREP_SUMMARY.md`
- ✅ `Docs/Archive/SECURITY_TEST_SUITE_SUMMARY.md`

---

## Consolidation Action

### Create: `Docs/Archive/AUDIT_ARCHIVE_NOTES.md`

This file will:
- Provide overview of all audit and progress documents
- Link to each archived document
- Explain the purpose of each document
- Serve as an index for the archive

**Contents will include**:
- Links to all 13 existing archive files
- Links to the 3 files being moved
- Brief description of each document's purpose
- Timeline of protocol development (v1.1 → v1.2 → v1.3)

---

## Link Cleanup Required

### Files to Update:

1. **README.md**:
   - ✅ Already references SPECIFICATION_v1.3.md correctly
   - ✅ References SPECIFICATION.md (keep - it's general spec)
   - ❌ Remove any references to archived audit docs (if any)
   - ✅ Ensure only v1.3 docs are prominently featured

2. **INDEX.md**:
   - ✅ Update to reflect only current production docs
   - ❌ Remove references to archived docs
   - ✅ Ensure clear separation between core and developer docs

3. **All Docs/**:
   - ✅ Verify internal cross-references still work after moves
   - ✅ Check Mermaid diagrams still render
   - ✅ Ensure no broken links

---

## Execution Plan

### Step 1: Move Files to Archive
```bash
# Root → Archive
mv PRODUCTION_READINESS_REPORT.md Docs/Archive/
mv PROTOCOL_V1.2_IMPLEMENTATION_COMPLETE.md Docs/Archive/

# Docs → Archive
mv Docs/PRODUCTION_READY.md Docs/Archive/
```

### Step 2: Create Consolidation Doc
- Create `Docs/Archive/AUDIT_ARCHIVE_NOTES.md`
- Link to all 16 archived documents
- Provide overview and timeline

### Step 3: Update Links
- Review README.md for archived doc references
- Update INDEX.md to remove archived doc references
- Verify all internal links

### Step 4: Verify
- Run link checker
- Verify Mermaid diagrams render
- Check file structure matches end state

---

## Final Directory Structure

```
/
├── README.md
├── LICENSE
├── CHANGELOG.md
├── CONTRIBUTING.md
├── RELEASE.md
├── SECURITY.md (policy)
├── Issues.md
├── Package.swift
├── Sources/
├── Tests/
├── Docs/
│   ├── INDEX.md
│   ├── SPECIFICATION_v1.3.md ⭐ FROZEN
│   ├── SPECIFICATION.md (general)
│   ├── API_STABILITY.md
│   ├── VERSIONING.md
│   ├── SECURITY.md (comprehensive)
│   ├── FAILURE_SEMANTICS.md
│   ├── BENCHMARKS.md
│   ├── FUZZING.md
│   ├── PERFORMANCE_TRACKING.md
│   ├── [15 developer/reference docs]
│   └── Archive/
│       ├── AUDIT_ARCHIVE_NOTES.md (NEW)
│       ├── PRODUCTION_READINESS_REPORT.md (MOVED)
│       ├── PROTOCOL_V1.2_IMPLEMENTATION_COMPLETE.md (MOVED)
│       ├── PRODUCTION_READY.md (MOVED)
│       └── [13 existing archive files]
└── Tools/
└── Examples/
```

---

## Summary

**Files to Move**: 3
- `PRODUCTION_READINESS_REPORT.md` → Archive
- `PROTOCOL_V1.2_IMPLEMENTATION_COMPLETE.md` → Archive
- `Docs/PRODUCTION_READY.md` → Archive

**Files to Create**: 1
- `Docs/Archive/AUDIT_ARCHIVE_NOTES.md` (consolidation index)

**Files to Update**: 2
- `README.md` (remove archived doc references if any)
- `INDEX.md` (remove archived doc references)

**Files Already Correct**: 38
- All core and developer docs are in correct locations

---

## Ready for Execution

✅ All files classified  
✅ Action plan defined  
✅ No deletions (only moves and consolidation)  
✅ Link cleanup identified  

**Awaiting confirmation to proceed with execution.**
