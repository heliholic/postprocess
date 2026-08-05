# CMSIS

Cortex-M core support and the STM32 register maps. Vendored: these files are
committed to this repository and change only when `cmsis.lock` is edited,
`tools/update-cmsis.sh` is run and the result committed.

## Where it comes from

CMSIS is two components from two upstreams, kept apart in this directory.

| | Upstream |
|---|---|
| `core/` | [ARM-software/CMSIS_6](https://github.com/ARM-software/CMSIS_6) |
| `device/STM32F7/` | [STMicroelectronics/cmsis_device_f7](https://github.com/STMicroelectronics/cmsis_device_f7) |
| `device/STM32H7/` | [STMicroelectronics/cmsis_device_h7](https://github.com/STMicroelectronics/cmsis_device_h7) |

`cmsis.lock` pins all three and is the file to edit to move any of them — see
[Updating](#updating).

**Core** is ARM's: `core_cm7.h`, the intrinsics, and the cache and MPU helpers.
Taken from ARM's own repository rather than the copy ST ships alongside Cube,
which is frozen at CMSIS 5.9.0. CMSIS 6 moved the M-profile headers into
`m-profile/` and is otherwise a drop-in; ST's device headers compile against it
unchanged.

**Device** is the per-part register map and the `IRQn_Type` list naming the
device interrupts. Only ST publishes these. The standalone `cmsis_device_*`
repositories carry the CMSIS pack without the HAL, Cube examples or BSP that
`STM32Cube*` includes.

Both are Apache-2.0; the licence text sits next to the headers it covers.

## What is here

The layout is flat: an include path points straight at `core/` or at a family
directory, with no `Include/` level in between.

```
core/                       ARM's CMSIS/Core/Include, copied whole
device/STM32H7/             the headers the build compiles against
    stm32h7xx.h                 umbrella header
    stm32h743xx.h               register map and IRQn_Type list, one per part
    stm32h723xx.h
    templates/              not compiled, not on the include path
        system_stm32h7xx.h      reference only — the compiled ones are ours
        system_stm32h7xx.c
```

`core/` is copied whole. Taking only the Cortex-M7 headers would save about
2 MB at the cost of a file list that breaks every time ARM restructures the
tree.

`device/` is filtered: F7 is 19 MB and H7 is 43 MB, nearly all of it register
maps for silicon this firmware does not run on. Each family keeps its umbrella
header, plus a part header and a system source per MCU in `cmake/mcu/`.

That list has one definition. `RFX_CMSIS_FAMILY`, `RFX_CMSIS_HEADER` and
`RFX_CMSIS_SYSTEM` in `cmake/mcu/<mcu>.cmake` are what the update script reads.
Each is named explicitly rather than derived from the part define: ST's naming
is a convention rather than a rule, and the H7 ships five system sources.

### templates/

**Nothing in `templates/` is compiled, and the directory is on no include
path.** `system_<family>.c`/`.h` and the startup templates are ST's own
bring-up code — clock tree, flash timing, MPU, caches, vector table — kept
here for reference. This firmware writes its own reset path rather than
compiling these.

Nothing here is modified. `tools/update-cmsis.sh --check` verifies that against
the digest in `cmsis.lock`; a hand-edited vendor header fails it.

## Using it

Link `cmsis::device`; the ST headers include `core_cm7.h`, so it pulls
`cmsis::core` with it. `rfx::core` links it on board builds, so anything in
`core/`, `helios/` or `targets/` includes the family header directly:

```c
#include "stm32h7xx.h"
```

The part define selecting the right register map (`STM32H743xx`) comes from
`RFX_MCU_DEFINES` in `cmake/mcu/<mcu>.cmake` and is applied to every object.

Include paths are `SYSTEM`. The firmware builds with `-Wconversion`,
`-Wsign-conversion`, `-Wundef` and `-Wcast-qual`, which vendor register maps do
not compile cleanly under.

## Updating

```sh
tools/update-cmsis.sh
```

The script holds no versions. The pins are in `cmsis.lock`, which is the file
to edit, so moving CMSIS is a data change rather than a code change — the same
split as `cmake/toolchain/arm-gnu-toolchain.lock.cmake` and `provision.cmake`.

Bump a tag and its commit in `cmsis.lock`, re-run, review the diff — every
vendored file is an unmodified upstream copy, so anything else in the diff is
an error — and build every board before committing.

The only line of `cmsis.lock` the script owns is `digest`, which it rewrites
over the tree it just produced.

Adding an MCU of a family already listed above needs no change to either file:
set `RFX_CMSIS_FAMILY`, `RFX_CMSIS_HEADER` and `RFX_CMSIS_SYSTEM` in its
`cmake/mcu/<mcu>.cmake` and re-run. A new family needs a row in `cmsis.lock`
first; the script names the family it could not find.
