# ChibiOS/RT

The kernel this firmware schedules on. Vendored: these files are committed to
this repository and change only when `chibios.lock` is edited,
`tools/update-chibios.sh` is run and the result committed.

## What is taken, and what is not

ChibiOS has two separable halves. **ChibiOS/HAL** drives peripherals; **RT** is
the kernel. They are not layered on each other — the HAL reaches the kernel
through the OSAL abstraction, and the kernel reaches nothing — so either can be
used without the other. This firmware takes RT and drives its own hardware.

That means no HAL, no OSAL, no `halconf.h`, no `mcuconf.h`, no board files and
none of ChibiOS's build system. What is here is the kernel, the OS library, and
the ARMv7-M port:

```
config/         chconf.h — hand-written, the only file here that is not vendored
license/        chlicense.h and the version headers ch.h opens with
rt/             the kernel: include/ and src/
oslib/          mailboxes, pipes, delegates: include/ and src/
port/           the ARMv7-M port, flattened from three upstream directories
    chcore.c        SVC_Handler, PendSV_Handler, port init
    chcoreasm.S     the context switch
    chcore.h  mpu.h  chtypes.h  ccportab.h
    STM32F7/cmparams.h   Cortex parameters, one per MCU family
    STM32H7/cmparams.h
templates/      upstream's chconf.h, the reference config/ is diffed against
LICENSE         GPLv3
```

Both `rt/src/` and `oslib/src/` are copied whole and compiled whole. Sources
for subsystems `chconf.h` switches off guard their entire contents and produce
empty objects, so the file list is independent of the configuration, unlike
upstream's makefiles.

`port/` is flattened because ChibiOS headers include each other by bare name
throughout; the three upstream directories are already one include path.

## Where it comes from

| | Upstream |
|---|---|
| everything | [ChibiOS/ChibiOS](https://github.com/ChibiOS/ChibiOS), `ver21.11.5` |

`chibios.lock` pins it and is the file to edit to move it — see
[Updating](#updating).

**Vendored rather than submoduled.** The repository is 445 MB; what this
firmware compiles is 1 MB of it. The rest is HAL ports, demos, testhal and
documentation for hardware this firmware does not run on, and a submodule puts
all of it in every clone and every CI job. Vendoring the subset also keeps the
unused parts of ChibiOS out of the tree.

`tools/update-chibios.sh` fetches sparsely and blobless, so an update pulls a
few megabytes rather than the whole repository.

## Licence

ChibiOS/RT is **GPLv3**. This firmware is GPL-3.0-or-later, so the kernel
imposes no additional obligation.

The port's `cmparams.h` files are Apache-2.0, as is upstream's `chconf.h`
template, which is why `config/chconf.h` keeps that header rather than this
tree's.

## What the kernel takes over

RT needs three things from the hardware. None of them come from this directory.

| | Where it is provided |
|---|---|
| **SysTick** | a tick driver RT would otherwise take from the HAL |
| **SVC** | `port/chcore.c`; it reaches the vector table on its own, since every vector in the part's startup assembly is weak |
| **process stack** | `startup_<part>.s` sets PSP and `CONTROL.SPSEL` before calling `main()`; the two stacks are carved in `<mcu>.ld` |

The process stack is a hard requirement. RT switches threads by swapping PSP,
and its SVC handler reads and writes PSP directly, so the thread that calls
`chSysInit()` must already be running on it. Left on MSP, the first context
switch corrupts silently rather than faulting.

PendSV is unused: `CORTEX_SIMPLIFIED_PRIORITY` is `FALSE`, selecting ChibiOS's
advanced kernel mode, in which SVC does the work. Its vector resolves to
`Default_Handler`.

## Interrupt priorities

The ARMv7-M port splits priorities into two classes. Every driver belongs to
one of them.

- Numerically below `CORTEX_MAX_KERNEL_PRIORITY` — **fast** interrupts. Never
  masked by `chSysLock()`, so no scheduler-induced jitter, and they may call no
  kernel function at all, not even the `*I()` forms.
- At or above it — **regular** interrupts. May signal semaphores, post to
  mailboxes and wake threads; masked by BASEPRI inside kernel critical
  sections.

`chSysLock()` masks with BASEPRI rather than PRIMASK, which is what makes the
fast class possible. The system tick runs at `CORTEX_MAX_KERNEL_PRIORITY`.

## Configuration

`config/chconf.h` is this firmware's copy of upstream's template and the only
file here that is not vendored: `tools/update-chibios.sh` neither writes it nor
covers it with the digest. Every divergence from the template is marked `RFX:`.
The settings that differ:

| Setting | | Why |
|---|---|---|
| `CH_CFG_ST_TIMEDELTA` | `0` | Periodic tick. Tickless requires `chcore_timer.h`, which is in the HAL. |
| `CH_CFG_USE_DYNAMIC` | `FALSE` | No dynamic allocation after init. |
| `CH_CFG_USE_MEMCORE` | `FALSE` | As above. |
| `CH_CFG_USE_HEAP` | `FALSE` | As above. |
| `CH_CFG_USE_FACTORY` | `FALSE` | Registers objects by name at runtime, and allocates to do so. |
| `CH_CFG_USE_MEMPOOLS` | `FALSE` | Forced: upstream ties the pools to `MEMCORE` even with static storage. |
| `CH_CFG_USE_OBJ_FIFOS` | `FALSE` | Forced: requires `MEMPOOLS`. |
| `CH_CFG_USE_JOBS` | `FALSE` | Forced: requires `MEMPOOLS`. |
| `CH_DBG_*` | follow `NDEBUG` | The template hard-codes them on; they cost cycles in every kernel call. |

Everything else stays at the template's value, minimising what an update has to
re-reconcile.

## Using it

Link `chibios::rt`. `rfx::core` does so on board builds, so anything in
`core/` includes the kernel directly:

```c
#include <ch.h>
```

That reach is wider than intended. Once `rfx::core` has sources of its own and
becomes `STATIC`, make `chibios::rt` `PRIVATE` to it, leaving
[src/core/rtos/](../../src/core/rtos/) as the only route and keeping `ch.h` out
of `helios/` and `targets/`. `cmake/check_layering.cmake` scans first-party
includes only and does not catch this.

Board builds only. The vendored port is ARMv7-M, so a host build compiles
nothing here; the concurrency interface in `core/rtos/` must stay thin enough
to carry a second implementation.

Include paths are `SYSTEM`, as CMSIS's are: the firmware builds with
`-Wconversion`, `-Wsign-conversion`, `-Wundef` and `-Wcast-qual`, which these
headers do not compile cleanly under.

The static library is built without LTO. The kernel is assembly, naked
functions and weak handlers intended to be overridden from other objects — the
same arrangement as the vector table. The image is still linked with
`RFX_LTO`.

## Updating

```sh
tools/update-chibios.sh
```

The script holds no versions. The pin is in `chibios.lock`, which is the file
to edit — the same data/logic split as `tools/update-cmsis.sh` and
`cmake/toolchain/arm-gnu-toolchain.lock.cmake`.

Bump the tag and its commit in `chibios.lock`, re-run, and review the diff:
every vendored file is an unmodified upstream copy, so anything else in the
diff is an error.

Then **diff `config/chconf.h` against the refreshed `templates/chconf.h`**.
Upstream adds and renames settings between releases, and an unset setting takes
the new default. The diff should reduce to the `RFX:` markers.

Build every board before committing.

```sh
tools/update-chibios.sh --check
```

verifies the vendored tree against the digest in `chibios.lock`, so a file
edited in place is detected. `config/` is excluded from the digest: kernel
settings belong there and are meant to be edited.
