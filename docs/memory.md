# Memory

Where a definition lives, and how to move it.

An undecorated definition lands in the largest SRAM the part has, which is
cached. The other memories are selected with a macro from
[core/common/memory.h](../src/core/common/memory.h), which reaches every
translation unit through `core.h`.

| Macro | Placement | Purpose |
|---|---|---|
| `FAST_CODE` | ITCM | off the flash bus, and out of the instruction cache |
| `FAST_DATA` | DTCM | single-cycle, never cached |
| `DMA_DATA` | the DMA pool | reachable by DMA and not cached |
| `BDMA_DATA` | the BDMA pool | the only memory BDMA reaches |
| `PERSISTENT` | DTCM, untouched | survives a warm reset |

```c
FAST_DATA   pidState_t pidState;        /* hot, read every control cycle */
DMA_DATA    u8 gyroRxBuf[16];           /* the SPI controller writes it */
PERSISTENT  u32 rebootReason;           /* still there after a reset */
FAST_CODE   void pidUpdate(void) { ... }
```

## What each part has

| | F722 | F745 | H723 | H743 |
|---|---|---|---|---|
| bulk, cached | SRAM1 176K | SRAM1 240K | AXI 320K | AXI 512K |
| DTCM | 64K | 64K | 128K | 128K |
| ITCM | 16K | 16K | 64K | 64K |
| DMA pool | SRAM2 16K | SRAM2 16K | D2 32K | D2 288K |
| BDMA pool | = SRAM2 | = SRAM2 | D3 16K | D3 64K |

The F7 has one DMA-reachable pool rather than the H7's two, so `BDMA_DATA`
lands beside `DMA_DATA` there. A `REGION_ALIAS` in the memory map does this
rather than a conditional in the header, so the macro means the same thing on
every part and no call site needs an `#ifdef`.

Both stacks are in DTCM on every part. They are placed from the top of it by
address arithmetic, and `sections_cm7.ld` asserts that they do not meet what
`FAST_DATA` claimed from the bottom:

```
DTCM overflow: stacks collide with FAST_DATA
```

Every other region reports an ordinary linker overflow, by name.

## DMA buffers must be declared

The default is cached memory, so a buffer a peripheral writes and the CPU then
reads is served from the cache with whatever it held before the transfer. This
is not a build error.

`DMA_DATA` places the buffer in a pool `SystemInit()` gives a non-cacheable MPU
region, which is why this firmware carries no cache maintenance calls. Any
buffer hardware reads or writes carries the macro.

## Initialisers

Every pool is a bss section, so a definition costs no flash and starts as
zeroes. An initialiser is a compile error:

```
error: only zero initializers are allowed in section '.bss.pool.fast'
```

Explicit zeroes are accepted — `= 0`, `= {0}`, `{}` — because the compiler
classifies on the value rather than the syntax. A non-zero starting value goes
in an init function. A table that is never written is `const` and belongs in
flash, which costs no RAM.

The alternative, a loadable pool, stores the zeroes of every buffer in flash
byte for byte: an 8K scratch array costs 8K of image. For `PERSISTENT` a load
address in flash would additionally make the reset path rewrite the value on
every boot.

`PERSISTENT` also requires a trivially constructible type. A C++ constructor
runs from `__libc_init_array()` long after `SystemInit()` decided not to clear
the region, on every boot, and would overwrite the retained value.

## How it is put together

| | |
|---|---|
| [linker/sections_cm7.ld](../src/core/platform/linker/sections_cm7.ld) | the layout, shared by every MCU |
| [linker/&lt;mcu&gt;.ld](../src/core/platform/linker/) | that part's memories, and the aliases the layout is written against |
| [common/memory.h](../src/core/common/memory.h) | the macros |
| [startup/startup_&lt;part&gt;.s](../src/core/platform/startup/) | the reset path — copies ITCM, zeroes the pools |
| [startup/system_&lt;part&gt;.c](../src/core/platform/startup/) | `persistentInit()` — clears `PERSISTENT` on a cold boot only |

Section names are `.bss.pool.<name>`. The `.bss.` prefix makes the compiler
emit them without storage and reject an initialiser. `pool` sits in the middle
because `-fdata-sections` names an ordinary variable's section
`.bss.<identifier>`, and a variable called `fast` or `dma` would otherwise
match the pattern meant for the pool; a dot cannot appear in an identifier, so
the collision cannot be written.

Those output sections must stay ahead of `.bss` in `sections_cm7.ld`: input
matching takes the first pattern that fits, and `*(.bss.*)` matches all of
them.

On a host build none of the macros expand to anything, so decorated code
compiles and runs in the unit tests unchanged.

## Consequences to account for

**Placed data is still garbage-collected if nothing references it.**
`--gc-sections` works per input section, and a translation unit contributes one
section per pool, so a buffer survives if anything else that translation unit
placed in the same pool is referenced and is dropped otherwise. Neither `used`
nor `retain` reliably overrides this for a section-placed definition. Decorate
what is used.

**A `FAST_CODE` call from flash costs a veneer.** ITCM is at address zero and
the image is at `0x08000000`, well outside the range of a Thumb `BL`, so the
linker inserts a long-branch stub: a few bytes and one indirect branch per call
site. `FAST_CODE` therefore pays off on functions that do real work rather than
on small helpers. The macro also carries `noinline`, since a `section`
attribute on an inlined function places nothing and LTO is on by default.
