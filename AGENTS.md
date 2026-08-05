# AGENTS.md

Working notes for agents and humans working in this repository.

## What this is

Flight control firmware for RC helicopters. A fresh C++20 design, not a port of
the old C Rotorflight tree; do not import its structure or idioms.

Freestanding: no exceptions, no RTTI, no dynamic allocation after init.
Fixed-capacity containers, ownership fixed at construction.

## Layout

```
src/
  core/       "Operating system" layer: scheduling, time, memory, sync, hardware
    platform/ Per-MCU: startup code, linker scripts
  helios/     The helicopter firmware, and main()
  targets/    Per-board definitions
cmake/        Toolchain, build helpers, layering check
  mcu/        Per-MCU architecture flags and part defines
ext/          Third-party code
  cmsis/      Vendored CMSIS — ARM core support, ST register maps
  chibios/    Vendored ChibiOS/RT — the kernel and its ARMv7-M port, no HAL
test/         Host unit tests (GoogleTest)
tools/        Scripts; also where the pinned toolchain is provisioned
docs/         Design notes
```

Two directory rules:

- **`src/` and `src/core/` contain directories only.** No source or header
  files at those levels; every component gets a subdirectory.
- **Headers sit next to their sources.** There is no separate include tree.
- **`.hpp` means C++ only; `.h` means C can include it.** A `.h` is either a C
  header or one written for both languages, and states the linkage itself
  under `#ifdef __cplusplus`. A `.hpp` declares nothing about linkage, because
  nothing in C reaches it. The extension is the contract: an `extern "C"` in a
  `.hpp`, or a C++ construct in a `.h` outside the guard, is a mistake in one
  of the two.

`main()` lives in `src/helios/main.cpp` but belongs to the `rfx::main` target
rather than `rfx::helios`: the test binary links `rfx::helios` and brings its
own `main()` from GoogleTest.

## Layering

```
rfx::main  ->  rfx::helios  ->  rfx::core  ->  rfx::common
```

`rfx::common` carries the include root and build defines. Dependencies run one
way only. `core/` knows nothing about helicopters; `helios/` is everything that
does.

[cmake/check_layering.cmake](cmake/check_layering.cmake) enforces the direction
on every build and fails it if `core/` includes from `helios/` or `targets/`,
or `helios/` from `targets/`. It scans includes because CMake permits
dependency cycles between `STATIC` libraries, so the link graph stops catching
this once the layer targets gain sources.

**Core must not include anything from `targets/`.** Where core needs the board,
it declares the interface itself — see
[src/core/board/board.h](src/core/board/board.h), which `src/targets/<board>/`
implements. The binding is resolved at link time.

## Boards and MCUs

A board declares the part fitted to it. Everything architectural is derived:

```
board (src/targets/<board>/target.cmake)   RFX_MCU, board sources, board defines
  └─ MCU (cmake/mcu/, src/core/platform/)  flags, startup code, link layout
```

A board owns its presets as well, in `src/targets/<board>/presets.json`, so a
board is one self-contained directory. `src/targets/` registers its own boards,
so the root file names the tree and never a board in it:

```
CMakePresets.json                 includes src/targets/presets.json — never a board
  └─ src/targets/presets.json     includes each src/targets/<board>/presets.json
       └─ <board>/presets.json    includes cmake/presets/common.json, inherits arm-debug
```

Two constraints apply when editing presets:

- The shared hidden presets (`base`, `arm`, `arm-debug`, `arm-release`) live in
  [cmake/presets/common.json](cmake/presets/common.json), not in
  `CMakePresets.json`. CMake lets a preset inherit only from its own file or
  from files that file includes, so a board file cannot reach into the file
  that includes it — neither the root file nor `src/targets/presets.json`. Each
  board file includes `common.json` itself, by the path up out of the tree.
  That path is what a future split of `src/targets/` must repoint.
- `src/targets/presets.json` lists each board's `presets.json` in its `include`
  array. CMake has no glob there, so that one line is the only registration a
  new board needs outside its directory. CI derives its board matrix from the
  `*-build` presets and needs no edit.

An MCU is two hand-written files under its own name. The flags are a build
setting and sit with the build system; the memory map sits with the code:

| File | Contents |
|---|---|
| `cmake/mcu/<mcu>.cmake` | `-mcpu`/FPU/float ABI, part defines, CMSIS device package |
| `src/core/platform/linker/<mcu>.ld` | Memory map, and the region aliases the shared layout is written against |

The section layout is not per-MCU. It lives once in
[src/core/platform/linker/sections_cm7.ld](src/core/platform/linker/sections_cm7.ld),
which every `<mcu>.ld` pulls in with `INCLUDE` after naming its memories. A new
MCU supplies `MEMORY` and the `BULK`, `DMAPOOL` and `BDMAPOOL` aliases and
inherits the layout. See [docs/memory.md](docs/memory.md).

Two more files sit in `core/platform/startup/`, both named for the part rather
than the MCU, since neither depends on the flash size that distinguishes one:

| File | Contents |
|---|---|
| `startup_<part>.s` | vector table, reset entry, and the bring-up of every section the linker script places |
| `system_<part>.c` | `systemPreInit()`, `SystemInit()`, and the clock tree they program |

`<part>` is ST's own part designator — `stm32f722xx`, the spelling of the
register-map header and of the `STM32F722xx` define, with the `xx` standing for
the pinout and flash size the register map does not depend on. Both files carry
it, so the pair shares one stem. `<family>`, used by the header below, is the
shorter `stm32f7xx`.

The `.cmake` file names both — `RFX_MCU_STARTUP` and `RFX_MCU_SYSTEM` — along
with the register map and ST's system template, `RFX_CMSIS_FAMILY`,
`RFX_CMSIS_HEADER` and `RFX_CMSIS_SYSTEM`, which `tools/update-cmsis.sh`
vendors into `ext/cmsis/`. A part from a family no board has used yet also
needs a row in [ext/cmsis/cmsis.lock](ext/cmsis/cmsis.lock) pinning that
family's package.

**Both files are first-party, and nothing regenerates them.** The startup files
began as the GCC templates in ST's CMSIS device package and keep its vector
tables, which name a part's interrupts in the order the NVIC takes them; that
part of the file is the only thing to take from ST when adding a part. The
reset path above the table, and all of `system_<part>.c`, are this tree's. ST's
system sources stay in `ext/cmsis/device/<family>/templates/` as a reference
for what the silicon expects at reset, off every include path and in no target;
its startup templates are not vendored at all.

**The reset path brings up every section itself**, in one sequence, and calls
`system_<part>.c` twice around it:

- `systemPreInit()` first — on the H7 the core supply, then the clock tree, the
  flash timing that goes with it and the SRAM clocks. It runs before `.data` is
  copied and `.bss` zeroed, so nothing it reaches may touch static storage,
  which is why there is no `SystemCoreClock` variable.
- then `FAST_CODE` into ITCM and `.data` out of flash, and `.bss` and every
  placement pool but `PERSISTENT` zeroed.
- then PSP from `__main_thread_stack_end__` and `CONTROL.SPSEL`, so `main()`
  runs on the process stack and the main stack is left to exceptions. ChibiOS
  swaps PSP to switch threads and its SVC handler reads PSP directly, so the
  thread that reaches `chSysInit()` must already be on it; left on MSP, the
  first context switch corrupts silently instead of faulting. Both stacks are
  then filled with `0x55555555` for high-water marks. They are carved in
  `core/platform/linker/<mcu>.ld`, which also defines the four symbols the
  kernel links against.
- `SystemInit()` last — the FPU, VTOR, `PERSISTENT`, the MPU regions and the
  caches. After the copies because the MPU makes ITCM read-only; before
  `__libc_init_array()` because the constructors are the first code to use the
  FPU. `PERSISTENT` is here rather than in the assembly because clearing it is
  a decision rather than a copy: the region survives a warm reset and is
  cleared only when a magic word kept inside it says the memory is cold.

There is no third hook. A single bring-up path cannot disagree with itself
about ordering. [docs/startup.md](docs/startup.md) covers the reset path, each
part's clock tree, the MPU regions, and what is left at reset defaults.

**`system_<family>.h` is the one filename ST dictates.** Every ST part header
includes it by bare name with no path, so it must exist and must be on the
include path; `core/platform/startup/` is, and `templates/` is not, which keeps
the first-party copy authoritative rather than shadowed by include order.

It declares what every part of that family provides — `systemPreInit()`,
`SystemInit()` and `sysClockHz()` — and holds no value of its own.

**Memory placement is a macro on the definition.** Ordinary data goes to the
part's bulk SRAM, which is cached; `FAST_CODE`, `FAST_DATA`, `DMA_DATA`,
`BDMA_DATA` and `PERSISTENT` from
[core/common/memory.h](src/core/common/memory.h) move it. Two consequences: a
buffer any peripheral DMAs to or from **must** carry `DMA_DATA`, since the
default is cached and nothing here does cache maintenance; and every pool is a
bss section, so an initialiser on a placed definition is a compile error rather
than a silently dropped value. See [docs/memory.md](docs/memory.md).

The frequencies stay in the `system_<part>.c` that programs them, and
`sysClockHz()` is the one number exported. Adding a part to a family already
present is one `system_<part>.c`; the header needs no edit.

Resolution lives in [cmake/RFXBoard.cmake](cmake/RFXBoard.cmake), which fails
the configure if any piece is missing. Parts sharing a memory map still get
their own set; there is no grouping mechanism.

**Everything below `main()` is C or assembly**, never C++. It runs before the C
runtime exists, so there are no constructors and no static storage to read.

**The two hooks `main()` calls are C as well** — `boardInit()` in
`src/targets/<board>/board.c` and `rtosStart()` in
[src/core/rtos/](src/core/rtos/) — both declared at file scope with C linkage,
so `main()` itself may be either language. They run with the runtime up and the
static constructors already called; the C is a linkage and implementation
choice rather than an ordering constraint.

The consequence is that `boardInit()` cannot construct C++ objects, so whatever
hands the board's hardware to the driver layer must be reachable from C. Where
a board needs C++ construction, the seam is one `extern "C"` function away.

Those C headers declare no C++ linkage of their own. C++ that needs the
register map or the clock tree includes
[src/core/common/system.h](src/core/common/system.h), which states the linkage
once and selects the family header from the part define, so board and driver
code carries neither an `extern "C"` nor an `#ifdef`.

Taking over an interrupt needs no registration and no edit to a table: every
vector is weak, so defining a function with the CMSIS name — `SysTick_Handler`,
`TIM2_IRQHandler` — anywhere in the image replaces it.

Host builds take `RFX_MCU=host` and link no image. Nothing in
`core/platform/startup/` is compiled there: it links against section bounds
only a board's linker script defines.

**`RFX_TARGET` is the only hardware knob.** `RFX_MCU` is derived and rejected
if passed on the command line.

MCU flags are applied at top-level directory scope, not as usage requirements,
so they reach every object including third-party code under `ext/` that links
no first-party target.

## Building

```sh
cmake --preset host-test && cmake --build --preset host-test && ctest --preset host-test
cmake --preset stm32h743-release && cmake --build --preset stm32h743-release
```

Host builds set no `RFX_TARGET` and link no image. Artifacts land in
`build/<preset>/src/targets/`.

Prerequisites are `cmake`, `ninja`, and optionally `clang-format`/`clang-tidy`.
Neither of the latter is guaranteed present; check before assuming.

## Toolchain

Pinned to one exact Arm GNU Toolchain release, currently **14.3.rel1 (GCC
14.3.1)**, in [cmake/toolchain/arm-gnu-toolchain.lock.cmake](cmake/toolchain/arm-gnu-toolchain.lock.cmake).

- Fetched automatically into `tools/` on the first ARM configure, SHA-256
  verified, gitignored. No bootstrap step.
- Referenced by absolute path, so a different `arm-none-eabi-gcc` on `PATH` is
  never picked up.
- A version mismatch fails the configure.

**Do not install the cross-compiler through a package manager** and do not add
it to the prerequisites. Distribution packages differ in both GCC and newlib.

`RFX_TOOLCHAIN_DIR` builds with an existing toolchain (still version-checked);
`RFX_TOOLCHAIN_URL` points at a mirror (hash must still match).

## Hard constraints

These are not style preferences. Breaking them produces firmware that fails on
hardware.

- **Firmware math is `float`. No MCU enables the double-precision FPU** —
  every one builds `-mfpu=<...>-sp-d16`, whatever the silicon carries. A
  `double` in a control loop costs hundreds of cycles in soft-float where a
  `float` costs one instruction. Three things enforce it: `RFXBoard.cmake`
  rejects an MCU selecting a DP FPU, `-Werror=double-promotion` fails the
  compile on a widened float (`sqrt` for `sqrtf`, a bare `1.0` literal), and
  [cmake/check_no_double.cmake](cmake/check_no_double.cmake) fails the link if
  a soft-float double routine reached the image. Write `1.0f`, `sqrtf`,
  `sinf`.
- **No cacheable region may be configured Write-Through.** Cortex-M7 erratum
  1259864 is unfixed on r1p1, which is what STM32H743 carries. Write-Back or
  non-cacheable only.
- **`.eh_frame` must be placed, not discarded.** `crtbegin.o` references it;
  `/DISCARD/` fails the link.
- **LTO and the vector table.** `RFX_LTO` defaults to ON. The table comes from
  ST's assembly, which LTO does not process, and the arrangement is verified:
  166 entries survive on the H743, 179 on the H723, unhandled vectors resolve
  to `Default_Handler`, and a strong C `SysTick_Handler` overrides the weak
  assembly one. The hazard is avoided rather than absent: the startup object is
  listed **before** the objects that override its handlers, which is the
  documented fix, so reordering it is a functional change. A vector table
  written in C would need `__attribute__((used))`; `KEEP()` alone does not
  preserve it, and section-placed functions still need `noinline`.
- **GCC 14 turned six C warnings into errors** (`implicit-function-declaration`,
  `int-conversion`, `incompatible-pointer-types`, `implicit-int`,
  `return-mismatch`, `declaration-missing-parameter-type`). ST's system source
  is compiled as first-party code and is clean under the full warning set,
  because the CMSIS headers it includes come in through `-isystem`. Vendor C
  added under `ext/` may still need explicit `-Wno-error=` entries.

[docs/architecture.md](docs/architecture.md) holds the full errata table and
the toolchain hazard list, including GCC PR 102018: quiet FP comparisons raise
spurious `FE_INVALID` on Cortex-M7 with the double-precision FPU at `-O1` and
above. Harmless while FP exception flags are ignored; relevant if FPU
invalid-operation trapping is ever enabled.

## Documentation style

Applies to every comment, document and commit message in this tree: C, C++,
assembly, CMake, shell, linker scripts, and the Markdown under `docs/`.

- **Professional technical register.** No conversational filler, no
  storytelling, no prose narrative, no asides to the reader. A comment is a
  statement of fact, not a paragraph about one.
- **Imperative mood.** `Configure PLL1 for a 960 MHz VCO`, not `This is where
  we configure the PLL`. Describe the subject; do not narrate the author.
- **Document why, not what.** The code already states what it does. A comment
  earns its place by recording a constraint that is not visible from the code:
  an erratum, a hardware requirement, an ordering dependency, a silicon
  revision. Do not paraphrase the statement below it.
- **No history.** Not what the code used to be, not what changed, not which
  alternative was rejected, not who changed it. Git records that.
- **Neutral tone.** State the constraint and stop. Do not justify the code
  against a hypothetical objection, do not argue against an alternative, and do
  not enumerate the consequences of violating the constraint beyond the one
  fact a reader needs.
- **Short and factual.** One line is the norm. A block is for a register
  layout, a clock tree, a table or a list.

  ```c
  /* HSE_VALUE has no default. The board sets RFX_HSE_HZ. */
  ```
- **A block comment opens and closes on lines of its own.** `/*` alone on the
  first line, `*/` alone on the last, ` * ` on everything between. A one-line
  comment stays on one line. Applies to C, C++ and linker scripts.

  ```c
  /*
   * SysTick runs at kernel priority so the handler may call
   * chSysTimerHandlerI().
   */
  ```

  Vendored files keep the style they arrived with. The ST sources under
  `core/platform/startup/` and everything below `ext/` are never restyled, so
  an update stays diffable against the pristine copy.
- **First-party sources open with the licence header**, verbatim from
  [docs/license-header.h](docs/license-header.h): the GPL-3.0-or-later notice
  with its SPDX identifier on the first line. It precedes any file comment or
  include. Vendored files under `ext/`, and ST's copies in
  `core/platform/startup/`, keep their own and never get it.

## Conventions

- Warnings come from `rfx_apply_warnings()` and are applied to first-party
  targets only — never to anything under `ext/`.
- `.clang-format` and `.clang-tidy` are authoritative. C++20, 100 columns,
  4 spaces, `rfx::` namespace.
- Third-party code lives under `ext/` and is built with its own settings.
  Submodules are the default; CMSIS and ChibiOS are vendored instead. CMSIS is
  a small set of headers that moves a few times a year; ChibiOS is 1 MB of
  kernel inside a 445 MB repository, nearly all of which is HAL ports and demos
  this firmware does not use. Vendoring both means a clone needs no submodule
  step and no build can pick up an unreviewed revision.

  Each is pinned in a lock file — [ext/cmsis/cmsis.lock](ext/cmsis/cmsis.lock),
  [ext/chibios/chibios.lock](ext/chibios/chibios.lock) — and applied by an
  update script that holds no versions of its own, the same data/logic split as
  the toolchain lock file. Vendored files are never edited;
  `tools/update-cmsis.sh --check` and `tools/update-chibios.sh --check` enforce
  that, and CI runs both. See [ext/cmsis/README.md](ext/cmsis/README.md) and
  [ext/chibios/README.md](ext/chibios/README.md).

  The one hand-written file under `ext/` is `ext/chibios/config/chconf.h`, the
  kernel's configuration. It sits outside the ChibiOS digest, and every
  divergence from upstream's template beside it is marked `RFX:`.

## Verifying a change

Run both build paths every time; they exercise different code:

```sh
cmake --preset host-test && cmake --build --preset host-test && ctest --preset host-test
cmake --preset stm32h743-release && cmake --build --preset stm32h743-release
```

Anything touching `cmake/mcu/`, `core/platform/` or the shared build settings
needs the other boards as well: `stm32f722-release`, `stm32f745-release`,
`stm32h723-release`, `devebox-release` and `nexus-release`. CI builds every
board, its list derived from the presets.

A board build produces no link warnings. Any warning is new.

The vector table is complete: 166 entries on the H743, 179 on the H723, 120 on
the F722, 114 on the F745. A change under `core/platform/startup/` requires
re-checking that count rather than trusting a green build: an image whose table
has been truncated, or whose handlers all point at the wrong place, links
successfully.

```sh
arm-none-eabi-size -A build/<preset>/src/targets/rfx_<board>.elf | grep isr_vector
```

An `INTERFACE` library that contributes nothing is externally
indistinguishable from one wired up correctly. When changing which sources a
target picks up, confirm the objects landed in the binary rather than trusting
a successful build.

## Open

Recorded in [docs/architecture.md](docs/architecture.md): component structure
inside `core/` and `helios/`, LTO policy, bootloader and flash header layout,
config storage.

The kernel is settled — ChibiOS/RT, so the model is preemptive. What sits on it
is not: the interrupt priority split, the concurrency interface `core/`
presents and its host implementation, and the thread set with its stack sizes.
Same file.
