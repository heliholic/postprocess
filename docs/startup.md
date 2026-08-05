# Startup and clocks

What happens between reset and `main()`, and the clock tree each MCU ends up
running. The code is in
[src/core/platform/startup/](../src/core/platform/startup/):

```
startup_<part>.s     vector table, reset entry, and the bring-up of every
                     section the linker script places
system_<part>.c      systemPreInit() and SystemInit(), and the clock tree,
                     which is private to this file
system_<family>.h    the name ST's part headers include, with no path.
                     Declares what every part of the family provides, and holds
                     no value of its own
```

All of it is first-party. The startup files began as the GCC templates in ST's
CMSIS device package and still carry its vector tables, which name a part's
interrupts in the order the NVIC takes them; the reset path above the table is
this tree's, and so is everything in the system sources.

**The frequencies do not leave the `.c`.** They are what `systemPreInit()`
programs. The one number exported is `sysClockHz()`, from which every other
clock is a fixed ratio a driver divides down for itself.

Everything there is C and declares no C++ linkage. C++ reaches it through a
header that states the linkage once and maps the part define onto a family
header, so board and driver code carries neither an `extern "C"` nor an
`#ifdef`.

## The reset path

Every section the linker script places is brought up in `startup_<part>.s`, in
one sequence — every one that is a copy or a fill, which is all of them but
`PERSISTENT`. The two calls into `system_<part>.c` are the halves of bring-up
that sequence needs, before and after. It is the same sequence on every part:

1. `MSP = __main_stack_end`
2. `systemPreInit()` — on the H7 the core supply first, then the clock tree,
   the flash timing that goes with it and the SRAM clocks
3. the sections, one pass each: `FAST_CODE` into ITCM and `.data`, both out of
   flash; `.bss` and every placement pool but `PERSISTENT` zeroed
4. `PSP = __main_thread_stack_end__`, `CONTROL.SPSEL = 1`, so `main()` runs on
   the process stack and the main stack is left to exceptions, which
   ChibiOS/RT's context switch requires
5. fill both stacks with `0x55555555`, for high-water marks
6. `SystemInit()` — the FPU, `VTOR`, `PERSISTENT`, the MPU regions and the
   caches
7. `__libc_init_array()` — static constructors
8. `main()`, which calls `boardInit()` and then `rtosStart()`
9. spin; `main()` does not return

**Everything up to and including step 2 runs without static storage.** Nothing
it calls may read or write a global: a read sees whatever the linker left in
RAM, and a write is overwritten a few instructions later by step 3. Constants
in flash are usable — `static const` tables, `#define`s.

That constraint is why there is no `SystemCoreClock` variable, CMSIS's name for
the CPU clock that `SystemInit()` conventionally assigns. The frequencies are
compile-time constants inside `system_<part>.c`, and `sysClockHz()` exports the
one other code reads, so no boot-time assignment has to be sequenced against
step 3 at all.

**The split is between what the copies need and what they must not have.**
`systemPreInit()` is what step 3 runs under: it writes RAM at the clock that
function programs, and on the H7 a write into a D2 pool is lost until the SRAM
it lives in has been clocked. `SystemInit()` is what step 3 must precede: the
MPU marks ITCM read-only, so nothing may write `FAST_CODE` once it is on.
Between them the pools sit in memory that is clocked, writable and uncached, so
none of the copying needs cache maintenance.

There is no third hook. A single bring-up path cannot disagree with itself
about ordering.

## What each half does

`systemPreInit()`, before the sections:

| | Step | Why here |
|---|---|---|
| 1 | core supply out of Run\* (H7 only) | the voltage scale cannot be raised under it |
| 2 | clock tree, flash timing | everything after it runs faster |
| 3 | memory system (H7 only) | SRAM clocks and errata, before the pools are zeroed |

`SystemInit()`, after them and before the constructors:

| | Step | Why here |
|---|---|---|
| 1 | FPU: CP10/CP11 full access | the constructors are the first code to use it |
| 2 | `VTOR = g_pfnVectors` | the table the linker placed, not the boot alias |
| 3 | `PERSISTENT` | anywhere after the copies; nothing else touches the region |
| 4 | MPU regions | must precede the caches |
| 5 | I-cache, D-cache | the region attributes must be in place first |

**`PERSISTENT` is the one section the reset path does not bring up itself**,
because bringing it up is a decision rather than a copy: the region survives a
warm reset, and is cleared only when a magic word kept inside it says the
memory is cold. `persistentInit()` in `system_<part>.c` is where that reads
clearly. Running after the copies, it is ordinary C with static storage behind
it: the magic word is a `PERSISTENT` variable rather than an address the code
works out for itself.

`systemPreInit()` starts by returning the RCC to its reset state — HSI on,
`CFGR` cleared, HSE and the PLLs off. The image may be entered from a
bootloader with a PLL already running, and the PLL registers are read-only
while one is.

**Every wait in this file is unbounded.** A crystal that does not start or a
PLL that does not lock halts bring-up. There is no console to report to and no
fallback clock, so the failure is a dead board rather than a subtly wrong
one.

## STM32F722

216 MHz, the part's maximum.

```
                 ┌─ /P ─ SYSCLK 216 ─┬─ /1 ── CPU, HCLK  216
  HSE ─ /M ─ xN ─┤                   ├─ /4 ── PCLK1       54
                 │                   └─ /2 ── PCLK2      108
                 └─ /Q ─ CK48M    48 ──────── USB, SDMMC
```

The PLL input must land in 1–2 MHz, so `M` depends on the crystal. The VCO is
432 MHz either way:

| HSE | M | PLL input | N | VCO | P | SYSCLK | Q | CK48M |
|---|---|---|---|---|---|---|---|---|
| 8 MHz | 4 | 2 MHz | 216 | 432 MHz | 2 | 216 MHz | 9 | 48 MHz |
| 25 MHz | 25 | 1 MHz | 432 | 432 MHz | 2 | 216 MHz | 9 | 48 MHz |

`TIMPRE` is set, which clocks the timers from HCLK instead of 2x PCLKx: every
timer counts at 216 MHz whichever APB it sits on. `CK48MSEL` selects PLLQ over
PLLSAI, so USB and SDMMC take their 48 MHz from the same VCO.

**Power.** 216 MHz requires voltage scale 1 *and* over-drive. Over-drive is
entered in two stages (`ODEN` → `ODRDY`, then `ODSWEN` → `ODSWRDY`) and only
while the CPU still runs off HSI, which is why the switch to the PLL is the
last step of the clock configuration.

**Flash.** 7 wait states at 216 MHz on scale 1 (RM0431 table 7), with the ART
accelerator and the prefetch buffer on. The latency is raised before the clock
and read back; the flash adopts the new value a few cycles after the write.

**MPU.** Two regions. Everything else stays on the default map through
`PRIVDEFENA`.

| Region | Base | Size | Attributes | Purpose |
|---|---|---|---|---|
| 0 | `0x00000000` | 16 KB | read-only, executable | ITCM — a write through a null pointer faults |
| 1 | `0x2003C000` | 16 KB | non-cacheable, shareable, XN | SRAM2 — the DMA pool, the `.sram2` section |

DTCM holds `.data`, `.bss` and the stacks and needs no region: TCM is never
cached regardless of the MPU configuration (AN4838), which is also why region 0
concerns write protection rather than caching.

## STM32F745

216 MHz, the part's maximum, on the same tree as the F722: same PLL, same
prescalers, same over-drive sequence, same 7 wait states at scale 1 (RM0385
table 7). `TIMPRE` is set and `CK48MSEL` selects PLLQ, as on the F722.

```
                 ┌─ /P ─ SYSCLK 216 ─┬─ /1 ── CPU, HCLK  216
  HSE ─ /M ─ xN ─┤                   ├─ /4 ── PCLK1       54
                 │                   └─ /2 ── PCLK2      108
                 └─ /Q ─ CK48M    48 ──────── USB, SDMMC
```

| HSE | M | PLL input | N | VCO | P | SYSCLK | Q | CK48M |
|---|---|---|---|---|---|---|---|---|
| 8 MHz | 4 | 2 MHz | 216 | 432 MHz | 2 | 216 MHz | 9 | 48 MHz |
| 25 MHz | 25 | 1 MHz | 432 | 432 MHz | 2 | 216 MHz | 9 | 48 MHz |

**The memory differs.** 320 KB of RAM against the F722's 256 KB, all of it in
the extra 64 KB of SRAM1, which moves SRAM2 up to `0x2004C000` — the one
address in the MPU table that differs from the F722's.

**MPU.** Two regions. Everything else stays on the default map through
`PRIVDEFENA`.

| Region | Base | Size | Attributes | Purpose |
|---|---|---|---|---|
| 0 | `0x00000000` | 16 KB | read-only, executable | ITCM — a write through a null pointer faults |
| 1 | `0x2004C000` | 16 KB | non-cacheable, shareable, XN | SRAM2 — the DMA pool, the `.sram2` section |

## STM32H743

480 MHz, the part's maximum, at voltage scale 0.

```
                 ┌─ /P ─ sys_ck 480 ─┬─ /1 ── CPU              480
  HSE ─ /M ─ xN ─┤                   └─ /2 ── HCLK, AXI        240
                 │                            └─ /2 ── PCLK1..4 120
                 └─ /Q ─ pll1_q 120 ───────── kernel clock option

  HSI48 ─────────────────────────────────────── USB             48
```

**Rev V or later only.** 480 MHz requires three things rev V introduced: the
higher maximum, a PLL VCO reaching 960 MHz, and voltage scale 0. Older silicon
has none of them, so `systemPreInit()` reads the revision from the top half of
`DBGMCU->IDCODE` and halts below rev V rather than clocking a part past its
rating. Current production is rev V; a board that halts here is built on older
stock.

The revision IDs do not sort by speed grade: rev Y is `0x1003` and rev X is
`0x2001`, both 400 MHz parts, and rev V is `0x2003`. The test is therefore a
floor at `0x2003` rather than a mask on the top bit.

| HSE | M | PLL input | RGE | N | VCO | P | sys_ck | Q | pll1_q |
|---|---|---|---|---|---|---|---|---|---|
| 8 MHz | 4 | 2 MHz | 1 | 480 | 960 MHz | 2 | 480 MHz | 8 | 120 MHz |
| 25 MHz | 5 | 5 MHz | 2 | 192 | 960 MHz | 2 | 480 MHz | 8 | 120 MHz |

Integer mode, no fractional divider, VCO in the wide range: 192–960 MHz on this
silicon against 836 MHz on rev Y, which is why 480 MHz is not an overclock of
the older part. `R` is left disabled. `Q` is enabled because SPI123 takes
`pll1_q` as its kernel clock by reset default, and 120 MHz is within the
200 MHz that interface is rated for.

`TIMPRE` stays 0: with the APBs at /2 that already yields 2x PCLK, so the
timers count at HCLK.

**Power supply.** `systemPreInit()` opens by writing `PWR->CR3`, which allows
the part to leave Run\* and raise its voltage scale. This part has no SMPS:
VCORE comes from the internal LDO, which is also the reset state, so the write
confirms rather than changes it. ST calls this step from the reset path, as
`ExitRun0Mode()`, because its own `SystemInit()` configures no clocks and the
supply is a board choice selected by `USE_PWR_*` defines; here it is neither,
so it opens the function that raises the scale.

`systemPreInit()` then selects scale 1 and waits for `VOSRDY`. **Scale 0 is
not a `VOS` encoding.** It is scale 1 plus the over-drive bit in
`SYSCFG->PWRCR`, which is why SYSCFG is clocked before the voltage step rather
than later with
the compensation cell, and why `VOSRDY` must be waited on a second time
afterwards.

**Flash.** 4 wait states for a 240 MHz AXI clock at scale 0 (RM0433 table 17).
Raised before the clock and read back. The programming delay field
(`WRHIGHFREQ`) in the same register is left at its reset value; it affects
flash programming only.

**USB.** Exactly 48 MHz is not available from this VCO, so USB takes HSI48.
HSI48 is accurate to about ±1% on its own, which USB full speed does not
accept; the CRS closes the remainder, trimmed against USB SOF by the driver.

**I/O compensation cell.** Enabled, running off CSI through SYSCFG. It holds
output slew within spec at these bus speeds.

**Memory system.** Two things are not available after reset:

- D2 SRAM comes out of reset unclocked. All three blocks are enabled, since the
  linker script places DMA buffers there.
- FMC bank 1 is enabled out of reset, and speculative reads into it lock the
  FMC out for 24 µs at a time. No board fits external memory, so it is
  disabled.

ST's SystemInit also limits the AXI interconnect's read issuing capability for
the AXI SRAM target, working around erratum ES0392, where rev Y can return
corrupted data. That is fixed in rev X, below the floor this firmware runs on,
and is not carried here.

**MPU.** Three regions. Everything else stays on the default map through
`PRIVDEFENA`.

| Region | Base | Size | Attributes | Purpose |
|---|---|---|---|---|
| 0 | `0x00000000` | 64 KB | read-only, executable | ITCM — a write through a null pointer faults |
| 1 | `0x30000000` | 512 KB | non-cacheable, shareable, XN | D2 SRAM — peripheral DMA, the `.dma_d2` section |
| 2 | `0x38000000` | 64 KB | non-cacheable, shareable, XN | D3 SRAM — BDMA, the `.sram_d3` section |

Region 1 is the smallest power of two covering the 288 KB fitted; the tail is
unmapped either way. AXI SRAM at `0x24000000` stays cached, being the bulk pool
rather than a DMA pool, and DTCM needs no region for the same reason as on the
F7.

## STM32H723

520 MHz at voltage scale 0.

```
                 ┌─ /P ─ sys_ck 520 ─┬─ /1 ── CPU              520
  HSE ─ /M ─ xN ─┤                   └─ /2 ── HCLK, AXI        260
                 │                            └─ /2 ── PCLK1..4 130
                 └─ /Q ─ pll1_q 130 ───────── kernel clock option

  HSI48 ─────────────────────────────────────── USB             48
```

**Not 550 MHz.** That is the datasheet maximum, and reaching it requires
setting `CPUFREQ_BOOST` in the option bytes, which disables the ECC on ITCM and
DTCM — the memories the control loop runs from. With the option bytes as
delivered, VOS0 caps the CPU at 520 MHz, so nothing here depends on how a board
was programmed before it arrived.

| HSE | M | PLL input | RGE | N | VCO | P | sys_ck | Q | pll1_q |
|---|---|---|---|---|---|---|---|---|---|
| 8 MHz | 4 | 2 MHz | 1 | 260 | 520 MHz | 1 | 520 MHz | 4 | 130 MHz |
| 25 MHz | 5 | 5 MHz | 2 | 104 | 520 MHz | 1 | 520 MHz | 4 | 130 MHz |

`P` is 1, which this part allows and the H743 does not; PLL1's P divider takes
even values only there. The bus dividers put the AXI and AHBs at 260 MHz
against a 275 MHz limit and the APBs at 130 MHz against 137.5 MHz.

**Power supply.** As on the H743: no SMPS, so `systemPreInit()` opens by
confirming the LDO and waiting for `ACTVOSRDY`. **Voltage scale 0 is reached
differently:** here it is the zero encoding of `VOS`, written directly. The
H743's SYSCFG over-drive bit does not exist on this part —
`SYSCFG_PWRCR_ODEN` is absent from its header.

**Flash.** 3 wait states for a 260 MHz AXI clock at scale 0 (RM0468 table 16).

**Memory system.** D2 SRAM is two 16 KB blocks rather than the H743's three,
and both are clocked on. There is no AXI SRAM read-issuing workaround; that is
an H743 rev Y erratum.

**MPU.** Three regions, the same shape as the H743's with this part's sizes.

| Region | Base | Size | Attributes | Purpose |
|---|---|---|---|---|
| 0 | `0x00000000` | 64 KB | read-only, executable | ITCM — a write through a null pointer faults |
| 1 | `0x30000000` | 32 KB | non-cacheable, shareable, XN | D2 SRAM — SRAM1 and SRAM2 back to back, the `.dma_d2` section |
| 2 | `0x38000000` | 16 KB | non-cacheable, shareable, XN | D3 SRAM — BDMA, the `.sram_d3` section |

## Rules this code is written to

- **Nothing up to `systemPreInit()` touches static storage.** See the reset
  path above.
- **No cacheable region is ever Write-Through.** Cortex-M7 erratum 1259864 is
  unfixed on r1p1 and lets Write-Through memory return stale data. Every region
  above is Write-Back or non-cacheable.
  - Flash is the one cacheable region left on the default map, which makes it
    Write-Through. Nothing stores to it in normal operation. A flash writer
    must handle both the erratum and cache maintenance, whatever attribute it
    runs under.
- **One source of truth for frequencies, and it is not shared.** Each
  `system_<part>.c` states its whole tree as compile-time constants
  (`RFX_SYSCLK_HZ`, `RFX_HCLK_HZ`, `RFX_PCLK1_HZ` and so on), private to that
  file, with `_Static_assert`s beside the PLL constants checking that the
  dividers still produce them. Nothing recomputes a frequency from the
  registers at runtime, and nothing outside reads one: `sysClockHz()` is the
  entire exported surface. Each part runs exactly one tree; the H743 achieves
  this by refusing to run on silicon that cannot hold it.

## Not configured, deliberately

Left at reset defaults until something needs them: PLL2 and PLL3, the CRS,
kernel-clock muxes other than USB (the defaults are PCLK for the USARTs and
I2Cs, `pll1_q` for SPI123), MCO outputs, LSE and the RTC, NVIC priority
grouping, and the flash programming delay on the H7.

## Changing it

**A new HSE frequency** needs a branch in the `#if HSE_VALUE ==` ladder in
`system_<part>.c` giving M, N and — on the H7 — the input range, plus the
frequency added to the board resolution's list of supported crystals. The
static assertions check the result: a crystal that cannot produce the
declared SYSCLK fails the build.

**A different target frequency** means editing the constants at the top of
`system_<part>.c` together with the PLL dividers, and on the H7 the voltage
scale and flash latency with them.

**Supporting the older H743 revisions** means a second PLL and flash
configuration selected where the halt is now, and with it every frequency in
`system_stm32h743xx.c` becoming a runtime value rather than a constant.

**A new part in an existing family** is one `startup_<part>.s`, one
`system_<part>.c`, and `RFX_MCU_STARTUP` and `RFX_MCU_SYSTEM` in its
`cmake/mcu/<mcu>.cmake`; the family header already declares what the pair must
define. Start from the nearest part's pair: the startup file differs only in
its vector table, which is the one part of it to take from ST's template for
the new part. Check everything in the system source — clock tree, voltage
scale, flash latency, the memory sizes in the MPU table — against the new
part.
