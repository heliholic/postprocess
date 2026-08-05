# Architecture notes

Working notes for a fresh C++ design. Nothing here is inherited from the old C
firmware, and nothing is settled until it is recorded as decided.

## Decided

- **C++20, freestanding.** No exceptions, no RTTI, no dynamic allocation after
  init. Fixed-capacity containers, ownership fixed at construction.
- **The compiler is pinned, not discovered.** One exact Arm GNU Toolchain
  release, hash-verified, fetched into `tools/`, referenced by absolute path,
  with a hard version check. Distribution packages differ in both GCC and
  newlib, which is enough to change the binary.
- **Two layers.** `src/core` is the "operating system": scheduling, time,
  memory, synchronisation, hardware access. `src/helios` is the helicopter
  firmware built on top. Dependencies run one way only, enforced on every build
  by `cmake/check_layering.cmake` rather than by the link graph, which cannot
  catch it once the layer targets become STATIC libraries.
- **Board ABI flags are global, not usage requirements.** `-mcpu`, FPU and
  float ABI are applied at top-level directory scope by `cmake/RFXBoard.cmake`
  so they reach every object in the image, including third-party code under
  `ext/` that links no first-party target. Propagating them through the link
  graph misses those objects until link time.
- **Host-buildable.** Helios compiles and runs on the host, so it can be tested
  without hardware. This determines where the seam inside `core` between logic
  and hardware access sits.
- **The clock tree is fixed at build time and stated in `system_<part>.c`.**
  `SystemInit()` programs one tree per part — 216 MHz on the F722 and F745,
  480 MHz on the H743, 520 MHz on the H723 — from the HSE the board declares.
  The frequencies stay private to the file that programs them: `sysClockHz()`
  is the only one exported, and every other clock is a fixed ratio a driver
  divides down for itself. Nothing recomputes a frequency from the registers at
  runtime, and static assertions check the PLL against the declared result.
  There is no `SystemCoreClock` variable: `SystemInit()` runs before `.data` is
  copied, so a variable it set would not survive to `main()`.
- **The H743 requires rev V silicon and halts on anything older.** 480 MHz
  needs the higher maximum, the 960 MHz VCO and voltage scale 0 that rev V
  introduced; rev X and rev Y have none of them and stop at 400 MHz. Supporting
  both would make every clock in the image a runtime value. `systemPreInit()`
  reads `DBGMCU->IDCODE` and halts rather than clocking a part past its rating.
  See [startup.md](startup.md).
- **Memory placement is explicit.** Ordinary data lives in the largest SRAM the
  part has, which is cached. The tightly-coupled memories are an explicit
  budget: `FAST_CODE` places a function in ITCM, `FAST_DATA` places data in
  DTCM, which is uncached and single-cycle. Both stacks are in DTCM
  unconditionally, and the linker script asserts on DTCM overflow rather than
  letting them grow into what `FAST_DATA` claimed. DMA buffers carry
  `DMA_DATA`, which places them in a pool with a non-cacheable MPU region; the
  default is cached, and an undecorated buffer is served from the cache. See
  [memory.md](memory.md).
- **No cacheable region is ever Write-Through.** Write-Back or non-cacheable
  only. This works around an unfixed Category A silicon erratum — see "Silicon
  errata" below.
- **Float only, and the double-precision FPU stays off.** Every MCU builds with
  the single-precision FPU, including parts whose silicon carries the
  double-precision unit. Flight math is `float`. A widened float is a compile
  error everywhere (`-Werror=double-promotion`); what the compiler cannot see
  becomes a libgcc soft-float call, and `cmake/check_no_double.cmake` rejects
  any image containing one. A DP FPU would make that link check ineffective,
  since double arithmetic would compile to VFP instructions and leave no symbol
  behind, so `cmake/RFXBoard.cmake` rejects an MCU that selects one.

## Silicon errata

STM32H743 carries a Cortex-M7 **r1p1** core, which determines whether a given
ARM erratum applies. References: ARM SDEN-1068427 (Cortex-M7 AT610/AT611
Software Developer Errata Notice) and ST ES0392.

**The table below is the H743's.** The STM32H723's core revision is not
established here, so nothing in the table applies to that part either way. The
rule that follows from it — never Write-Through — is applied on every part
regardless.

**GCC has no `-mfix-*` flag for any Cortex-M7 erratum**; the only Cortex-M one
is `-mfix-cortex-m3-ldrd`. Every item below is a source-level obligation.

| ID | Cat | r1p1 | Consequence |
|---|---|---|---|
| 1259864 | **A** | **Affected** | Write-Through memory can return stale data |
| 1313001 | C | Open | DMB required between cache maintenance and a store |
| 1315869 | C | Open | ARM: no workaround necessary — compilers do not emit the trigger |
| 837070 | B | Fixed in r0p2 | Not applicable. Would apply to an F7 port (r0p1) |
| 833872 | C | Fixed in r0p2 | Not applicable |
| 838869 | — | Cortex-M4 only | Not applicable |
| 3092511 | — | Debug only | Debugger may halt at the wrong address; an OpenOCD concern |

**1259864 constrains the design.** A sequence of stores and loads to
Write-Through memory can return stale data. It is fixed only in r1p2, so on
this part it is permanently live. ARM state there is no direct workaround and
recommend using the MPU to make such memory Write-Back, or disabling the cache
for code that touches it. Hence the rule above: Write-Back or non-cacheable,
never Write-Through. Write-Through is otherwise an attractive choice for DMA
buffers.

1313001 is satisfied by the CMSIS cache functions, which carry the barriers. It
applies only to hand-rolled cache maintenance.

## Toolchain hazards

Findings against the pinned Arm GNU Toolchain 14.3.rel1 (GCC 14.3.1). None
block the pin — there is no known wrong-value miscompilation for this target —
but each carries a cost if overlooked.

**Quiet FP compares raise spurious FE_INVALID** — [GCC PR
102018](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=102018), open. On
`-mcpu=cortex-m7`, specifically because `+fp.dp` enables the double-precision
FPU, GCC emits the signalling `vcmpe.f64` where a quiet `vcmp.f64` is required,
for builtins such as `__builtin_islessequal`. Comparing against NaN then raises
`FE_INVALID` spuriously. Present at `-O1/-O2/-O3` and under LTO; absent at
`-O0/-Os`. Cortex-M4 and M55 are unaffected.

**Not this configuration.** The bug requires the double-precision FPU, and no
MCU enables it; the `-sp-` variant emits no `f64` compare at all. It returns if
a DP FPU is ever selected, which is one of the reasons the build rejects one.
Even then the results and branches are correct: it matters only with FPU
invalid-operation *trapping* enabled to hunt NaNs in flight math, where the
traps would fire on ordinary comparisons.

**LTO deletes the vector table.** Nothing in the program calls it — only
hardware does — so link-time optimisation removes it. `KEEP()` in the linker
script is necessary but documented as insufficient; the table also needs
`__attribute__((used))`. Related, and all live in current GCC:

- Weak ISR symbols defined in assembly are dropped under LTO. The fix is link
  order (weak-providing objects before strong) or the `interrupt` attribute.
- A `section` attribute is ignored when a function is inlined, which LTO makes
  far more likely. Anything placed by section — `.RamFunc` flash routines
  especially — needs `noinline`.
- `-g` together with `-flto` is officially experimental.

`RFX_LTO` defaults to ON, and the vector table lives in `startup_<part>.s`
rather than in C. That avoids the first hazard, since LTO
does not process assembly and there is no `used` attribute to forget, and puts
the weight on the second.

Measured on the images this tree builds, with GCC 14.3.1:

- The table survives whole: 166 entries on the H743, 179 on the H723, 120 on
  the F722, 114 on the F745.
- Unhandled vectors resolve to `Default_Handler`.
- A strong `SysTick_Handler` defined in C **does** override the weak assembly
  definition; the slot holds the C symbol.

The documented failure does not reproduce here, but it is avoided rather than
absent. `core/platform/startup/CMakeLists.txt` lists the startup file first,
putting the weak-providing object ahead of the objects that override it, which
is the recommended fix. Reordering those sources is a functional change, and
the measurements above are what catch it.

The remaining two hazards apply once there are `.RamFunc` routines to place.

**GCC 14 turned six C warnings into errors** — `implicit-function-declaration`,
`int-conversion`, `incompatible-pointer-types`, `implicit-int`,
`return-mismatch`, `declaration-missing-parameter-type`. First-party code is
clean under them. Vendor C under `ext/` is the likely source of violations, and
since these are errors *by default*, keeping `ext/` out of
`rfx_apply_warnings()` does not help: those targets need explicit `-Wno-error=`
entries. Vendored CMSIS compiles no C of its own, and its include paths are
`SYSTEM`.

In C++, GCC 14 also stopped including `<algorithm>` and `<cstdint>`
transitively, the usual cause of "built on 13, fails on 14".

**Code size versus 13.3.1.** Reports of libgcc complex-arithmetic routines
(`__mulsc3`, `__muldc3`, `__divsc3`, `__divdc3`) growing in 14.x, cause never
identified; some projects reverted. Only reachable through C99 `_Complex`,
which this firmware does not use. Worth re-measuring once there is real code;
changing the pin is a one-line edit in the lock file.

## Open

- The components inside `core/` and `helios/`, and where the hardware-access
  seam inside `core/` sits.
- LTO policy: keep `RFX_LTO` on and commit to the `used`/`noinline`/link-order
  discipline above, or default it off until a built image has been verified to
  boot.
- Concurrency model. The kernel is settled — ChibiOS/RT, vendored under
  `ext/chibios/` and started from `core/rtos/`, so the model is preemptive
  rather than a cooperative main loop. Open on top of it:
  - Which interrupts sit above `CORTEX_MAX_KERNEL_PRIORITY` and so may call no
    kernel function, and which sit at kernel priority and may wake a thread.
    The gyro path decides the rest: zero jitter or the ability to signal, not
    both. See
    [ext/chibios/README.md](../ext/chibios/README.md#interrupt-priorities).
  - The concurrency interface `core/` presents above the kernel, and its host
    implementation. `test/` links `rfx::helios` on the host, where the ARMv7-M
    port compiles nothing, so a second backend is required rather than
    optional. Retrofitting it after `helios/` is written against ChibiOS
    semantics costs considerably more than designing for it now.
  - Thread set, priorities and stack sizes. DTCM is 128 K and thread working
    areas are `.bss`.
- Bootloader and firmware-header layout. Flash currently starts at 0x08000000.
- Config storage: wear-levelled internal flash versus external SPI flash.
