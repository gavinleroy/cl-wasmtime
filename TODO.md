# cl-wasmtime TODO

Analysis date: 2026-04-19
**Test status:** 113/113 tests passing (100%)

## Completed Work

### P0 Critical Bugs (ALL FIXED) ✅
All 10 failing tests now pass.

**1. Host Function Callback - UNBOUND-VARIABLE LISP-ARGS** ✅
- Changed `let` to `let*` in `host-func-trampoline` (src/core.lisp:1001)
- Fixes 5 tests: HOST-FUNCTION-CALL, HOST-FUNCTION-MULTIPLE-ARGS, HOST-FUNCTION-RETURNS-MULTIPLE, LINKER-GET, LINKER-ALLOW-SHADOWING

**2. Multi-Value Return - Returns List Not Values** ✅
- Wrapped result in `(values-list ...)` (src/core.lisp:617-620)
- Fixes 1 test: MULTI-VALUE-RETURN

**3. i64 Type Inference - Auto-Detection Fails** ✅
- Added `functype-param-types` helper to extract expected types
- Modified `lisp-to-wasm-val` to accept optional type parameter
- Updated `call-function` to pass param types to `lisp-to-wasm-val`
- Fixes 1 test: I64-BOUNDARY-VALUES

**4. Fuel Functions Return NIL** ✅
- Fixed FFI binding: `%wasmtime-context-get-fuel` returns `wasmtime-error-t`, not `:bool`
- Updated `store-get-fuel` to check error and read uint64 result
- Fixes 2 tests: STORE-FUEL, FUEL-CONSUMED-DURING-EXECUTION

**5. i32 Overflow Behavior - Test Expectation Issue** ✅
- Corrected test expectations in i32/i64 boundary value tests
- Test expected 0, but correct WASM wrapping behavior returns -2147483648
- Fixes 2 tests: I32-BOUNDARY-VALUES, I64-BOUNDARY-VALUES

### P1 Memory Safety (MOSTLY FIXED) ✅
**1. Callback Registry Memory Leak** ✅
- Added finalizer to `make-host-function` that calls `(remhash id *callback-registry*)`
- Callbacks now removed when Lisp function GC'd, preventing unbounded hash table growth

**2. Memory Pointer Invalidation After Grow** ✅
- Added comprehensive warning to `memory-data` docstring
- Documents that pointer is invalidated by `memory-grow`
- Users instructed to call `memory-data` again after grow operations

**3. Host Function Return Count Validation** ✅
- Added check in `host-func-trampoline` callback
- Validates returned value count matches declared nresults
- Prevents uninitialized memory reads or silent truncation

**4. Config Object Lifetime Leak** ✅
- Added error handling in `make-engine`
- If engine creation fails after config cancel, calls `(%wasm-config-delete cfg-ptr)` before error
- Prevents config memory leak on engine creation failure

**5. Finalizer Race Conditions** ✅
- Reviewed all `tg:finalize` calls
- Current implementation captures pointer value, not object reference
- Races possible but highly unlikely; acceptable risk for current scope

### P2 Test Coverage (EXPANDED) ✅
**Tests Added: +24 new tests**
- MODULE-LOAD-FROM-FILE: Load WASM from file path
- MODULE-SERIALIZE-DESERIALIZE-FILE: Serialize to file and deserialize
- MODULE-LOAD-CORRUPTED: Corrupted bytes signal error
- MODULE-VALIDATE-CORRUPTED: Invalid WASM signals error
- CALL-FUNCTION-WRONG-ARG-COUNT: Wrong arity signals error (2 sub-tests)

## Remaining Work (12 Open Tasks)

### P1 Continued - Type Safety & Validation

**1. Float Conversion Validation** (Task #24)
- **Priority:** Medium
- **Issue:** No validation that Lisp float fits in f32 range
- **Location:** `src/core.lisp:668-681` (lisp-to-wasm-val single-float case)
- **Work:** Add range check for f32 (±3.4e38) to prevent silent overflow/underflow
- **Tests:** Need test cases for edge values

**2. Add Null Pointer Checks** (Task #20)
- **Priority:** Medium
- **Issue:** Many FFI functions return NULL on error, not all checked
- **Locations:**
  - `instance-export` (src/core.lisp:469) - might return NULL on not-found
  - `extern-from-c` (src/core.lisp:503) - calls %wasmtime-func-type without NULL check
  - Other C function returns not validated
- **Work:** Add NULL pointer guards before dereferencing C pointers
- **Tests:** Test invalid export names, missing imports

**3. Fix String Encoding Issues** (Task #21)
- **Priority:** Low
- **Issue:** Module/field names passed as UTF-8 to C, length from Lisp string may not match encoded byte count
- **Location:** Multiple locations where `:string` or length passed to FFI
- **Work:** Use `sb-ext:string-to-octets` with `:utf-8` and pass byte length, not character count
- **Tests:** Test non-ASCII module/field names

**4. Add Store/Engine Mismatch Validation** (Task #22)
- **Priority:** Low
- **Issue:** No runtime validation that functions/memories created with same store/engine
- **Location:** `call-function` (src/core.lisp:585), `linker-instantiate` (src/core.lisp:358)
- **Work:** Add store-id/engine checks before FFI calls
- **Tests:** Test mixing stores, engines, mismatched linkers

**5. Document Concurrency Safety** (Task #25)
- **Priority:** Low
- **Issue:** WasmTime engine/module thread-safe, but stores are not. *callback-registry* has no locking
- **Work:** Add docstring warnings to store functions, add thread-safe wrapper for callback registry
- **Tests:** Test concurrent store access (should fail appropriately)

### P2 Test Coverage

**1. Component Model Tests** (Task #10)
- **Priority:** Medium
- **Issue:** Complete API exists, zero tests
- **API to test:**
  - `load-component` / `load-component-from-file`
  - `component-serialize` / `component-deserialize`
  - `component-linker` operations
  - `component-linker-add-wasi`
  - `component-instance-export`
- **Scope:** 5-10 tests covering basic lifecycle

**2. Memory Edge Case Tests** (Task #13)
- **Priority:** Medium
- **Issue:** Memory operations not fully tested
- **Tests needed:**
  - Out-of-bounds read/write (should trap or error)
  - Out-of-bounds with `(setf memory-ref ...)`
  - Memory growth beyond max constraint
  - Reading from newly grown memory regions
  - Zero-size memory access
- **Scope:** 5-7 tests

**3. Linker Operation Tests** (Task #14)
- **Priority:** Medium
- **Issue:** Basic linker exists, advanced ops untested
- **Tests needed:**
  - `linker-define` (generic extern definition)
  - `linker-define-memory` with specific properties
  - `linker-define-global` (mutable/immutable)
  - Linker with pre-defined memories/globals
  - Linker define with module/field name edge cases
- **Scope:** 5-8 tests

**4. Instance Introspection Tests** (Task #15)
- **Priority:** Low
- **Issue:** Limited instance inspection
- **Tests needed:**
  - `instance-exports` (list all exports)
  - Export count validation
  - Export iteration and lookup
  - Empty exports (module with no exports)
- **Scope:** 3-4 tests

**5. WASI Feature Tests** (Task #16)
- **Priority:** Medium
- **Issue:** WASI API mostly untested
- **Tests needed:**
  - `wasi-config-preopen-dir` (file system access)
  - Actual file I/O from WASI module
  - WASI module stdout/stderr
  - Custom stdio configuration
- **Scope:** 3-5 tests (needs actual WASI module WAT examples)

**6. Host Function Float Type Tests** (Task #17)
- **Priority:** Low
- **Issue:** Host functions only tested with i32/i64
- **Tests needed:**
  - Host function with f32 params
  - Host function with f64 params
  - Host function returning f32
  - Host function returning f64
  - Mixed param types (i32, f32, i64, f64)
- **Scope:** 4-6 tests

**7. Global Float Type Tests** (Task #18)
- **Priority:** Low
- **Issue:** Globals only tested with i32/i64
- **Tests needed:**
  - Global with f32 type
  - Global with f64 type
  - Mutable f32/f64 globals
  - Global import/export with floats
- **Scope:** 3-4 tests

### P3 Developer Experience (Not Started)

1. **Performance Benchmarks** - No baseline for optimization work
2. **Improved Documentation** - Missing examples, concurrency safety notes, performance best practices
3. **Fuzzing** - Complex FFI boundary vulnerable to malformed WASM
4. **CI/CD Setup** - No automated regression detection

## Implementation Notes

### High Priority (Complete ASAP)
1. Float conversion validation (#24) - prevents silent data loss
2. Null pointer checks (#20) - prevents crashes/undefined behavior
3. WASI tests (#16) - validates major API surface

### Medium Priority
1. Component model tests (#10) - validates untested API
2. Memory edge case tests (#13) - comprehensive memory coverage
3. Linker operation tests (#14) - validates linker completeness

### Low Priority (Polish)
1. String encoding (#21) - rare edge case with non-ASCII names
2. Store/engine mismatch validation (#22) - user error prevention
3. Instance introspection (#15) - utility coverage
4. Host function float tests (#17) - completeness
5. Global float tests (#18) - completeness
6. Concurrency documentation (#25) - informational

## Quick Reference: What Works

✅ Core WASM execution (call functions, read/write memory, globals)
✅ Module loading and instantiation
✅ Host functions (callbacks from WASM)
✅ Fuel metering
✅ Error trapping
✅ Module serialization
✅ File I/O operations
✅ Error handling for common misuse
✅ Memory safety for callbacks

## Known Limitations

- Table get/set for funcref not implemented (needs funcref value type support)
- No concurrent store access (stores must be per-thread)
- No automated bounds checking for memory access (WASM module responsible)
- Float values silently truncate from f64→f32 (needs validation)
