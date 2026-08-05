/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * This file is part of RFX Firmware.
 *
 * Copyright (C) 2026 Rotorflight Project.
 *
 * RFX Firmware is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * RFX Firmware is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <https://www.gnu.org/licenses/>.
 *
 * Based on the GCC startup template for this part in ST's CMSIS device
 * package, Copyright (c) 2019 STMicroelectronics, Apache-2.0. The vector
 * table and the weak handler aliases below are still ST's, naming this part's
 * interrupts in the order the NVIC takes them. The reset path above them is
 * this firmware's own.
 */

/*
 * STM32H723 reset path: the vector table, and everything that runs
 * before the C runtime exists.
 *
 * Every section the linker script places is brought up here, in one sequence,
 * with no C helper alongside it:
 *
 *   1. MSP = __main_stack_end, the top of DTCM.
 *   2. systemPreInit(): the clock tree, the flash timing that goes with it, and
 *      the SRAM clocks. Everything the copies below need before they may
 *      write RAM.
 *   3. The sections, in one pass each: FAST_CODE into ITCM and .data out of
 *      flash, .bss and the placement pools zeroed. Every section but
 *      PERSISTENT, which is not zeroed at all on a warm reset and is left to
 *      SystemInit().
 *   4. PSP = __main_thread_stack_end__ and CONTROL.SPSEL = 1, so main() runs
 *      on the process stack and the main stack is left to exceptions.
 *      ChibiOS/RT swaps PSP to switch threads and its SVC handler reads it
 *      directly, so the thread reaching chSysInit() must already be on it.
 *   5. Both stacks filled with a known pattern, for high-water marks.
 *   6. SystemInit(): the FPU, VTOR, PERSISTENT, the MPU regions and the
 *      caches. After the copies, because the MPU marks ITCM read-only and
 *      nothing may write FAST_CODE once it does; before the constructors,
 *      because they are the first code to use the FPU.
 *   7. __libc_init_array(), the static constructors, then main().
 *
 * Nothing up to and including step 2 has static storage to work with: .data
 * holds whatever the linker left in RAM and .bss is not zeroed, so nothing
 * called from there may read or write a variable. The symbols below are linker
 * symbols — addresses, not storage.
 *
 * Taking over an interrupt needs no edit here. Every vector is weak and
 * resolves to a spinning Default_Handler, so a function defined anywhere in
 * the image under the CMSIS name replaces it. See docs/startup.md.
 */

.syntax unified
.cpu cortex-m7
.fpu softvfp
.thumb

/*
 * The section bounds come from core/platform/linker/sections_cm7.ld, which
 * places every section named below, and the stack symbols from
 * core/platform/linker/<mcu>.ld, which carves both stacks out of DTCM.
 *
 *   mem_copy <start>, <end>, <load>   copy [start, end) in from <load>
 *   mem_fill <start>, <end>, <word>   fill [start, end) with <word>
 *
 * Both work in words, which every bound the linker script defines is aligned
 * to. An expansion is one whole step of the sequence above, so clobbering
 * r0-r3 costs nothing. Their labels are numeric and so local to the
 * expansion.
 */
.macro mem_copy start, end, load
  ldr   r0, =\start
  ldr   r1, =\end
  ldr   r2, =\load
1:
  cmp   r0, r1
  bhs   2f
  ldr   r3, [r2], #4
  str   r3, [r0], #4
  b     1b
2:
.endm

.macro mem_fill start, end, word
  ldr   r0, =\start
  ldr   r1, =\end
  ldr   r2, =\word
1:
  cmp   r0, r1
  bhs   2f
  str   r2, [r0], #4
  b     1b
2:
.endm

/*
 * The reset entry point. The core arrives here in Thread mode, privileged, on
 * the main stack.
 */
.section .text.Reset_Handler,"ax",%progbits
.global Reset_Handler
.type Reset_Handler, %function

Reset_Handler:
  ldr   sp, =__main_stack_end

/* The clock tree, the flash timing that goes with it, and the SRAM clocks. */
  bl    systemPreInit

/* FAST_CODE into ITCM, and .data, both out of flash. */
  mem_copy __itcm_start, __itcm_end, __itcm_load
  mem_copy __data_start, __data_end, __data_load

/* .bss, then each pool it zeroes, in the order sections_cm7.ld places them. */
  mem_fill __bss_start, __bss_end, 0
  mem_fill __fast_start, __fast_end, 0
  mem_fill __dma_start, __dma_end, 0
  mem_fill __bdma_start, __bdma_end, 0

/* main() and every thread run on the process stack; exceptions keep MSP. */
  ldr   r0, =__main_thread_stack_end__
  msr   psp, r0
  movs  r0, #2                          /* SPSEL = 1, privileged */
  msr   control, r0
  isb

/*
 * Fill both stacks, so their high-water marks can be read back.
 * CH_DBG_FILL_THREADS covers thread working areas, but these two are carved
 * by the linker script and ChibiOS never sees them. Nothing is live on either
 * yet, and they are contiguous — process stack below main — so one pass
 * covers both.
 */
  mem_fill __main_thread_stack_base__, __main_stack_end, 0x55555555

/* The rest of bring-up, now that it has RAM to work with. */
  bl    SystemInit

/* The static constructors, over the .init_array the linker script placed. */
  bl    __libc_init_array

/* main(), the entry point in the C/C++ sources. It should not return. */
  bl    main

/* Spin here in case main() returns */
9:
  b     9b
  .size Reset_Handler, .-Reset_Handler


/*
 * Every vector not defined elsewhere in the image lands here. Spinning
 * preserves the state that led to it for a debugger to read.
 */
.section .text.Default_Handler,"ax",%progbits
.global Default_Handler
.type Default_Handler, %function

Default_Handler:
9:
  b     9b
  .size Default_Handler, .-Default_Handler


/******************************************************************************
*
* The vector table, which the linker script places at the start of flash.
* SystemInit() points VTOR at it rather than at whatever the boot mapping
* aliases to zero.
*
*******************************************************************************/

.section .isr_vector,"a",%progbits
.global g_pfnVectors
.type g_pfnVectors, %object

g_pfnVectors:
  .word     __main_stack_end
  .word     Reset_Handler

  .word     NMI_Handler
  .word     HardFault_Handler
  .word     MemManage_Handler
  .word     BusFault_Handler
  .word     UsageFault_Handler
  .word     0
  .word     0
  .word     0
  .word     0
  .word     SVC_Handler
  .word     DebugMon_Handler
  .word     0
  .word     PendSV_Handler
  .word     SysTick_Handler

  /* External Interrupts */
  .word     WWDG_IRQHandler                   /* Window WatchDog              */
  .word     PVD_AVD_IRQHandler                /* PVD/AVD through EXTI Line detection */
  .word     TAMP_STAMP_IRQHandler             /* Tamper and TimeStamps through the EXTI line */
  .word     RTC_WKUP_IRQHandler               /* RTC Wakeup through the EXTI line */
  .word     FLASH_IRQHandler                  /* FLASH                        */
  .word     RCC_IRQHandler                    /* RCC                          */
  .word     EXTI0_IRQHandler                  /* EXTI Line0                   */
  .word     EXTI1_IRQHandler                  /* EXTI Line1                   */
  .word     EXTI2_IRQHandler                  /* EXTI Line2                   */
  .word     EXTI3_IRQHandler                  /* EXTI Line3                   */
  .word     EXTI4_IRQHandler                  /* EXTI Line4                   */
  .word     DMA1_Stream0_IRQHandler           /* DMA1 Stream 0                */
  .word     DMA1_Stream1_IRQHandler           /* DMA1 Stream 1                */
  .word     DMA1_Stream2_IRQHandler           /* DMA1 Stream 2                */
  .word     DMA1_Stream3_IRQHandler           /* DMA1 Stream 3                */
  .word     DMA1_Stream4_IRQHandler           /* DMA1 Stream 4                */
  .word     DMA1_Stream5_IRQHandler           /* DMA1 Stream 5                */
  .word     DMA1_Stream6_IRQHandler           /* DMA1 Stream 6                */
  .word     ADC_IRQHandler                    /* ADC1, ADC2 and ADC3s         */
  .word     FDCAN1_IT0_IRQHandler             /* FDCAN1 interrupt line 0      */
  .word     FDCAN2_IT0_IRQHandler             /* FDCAN2 interrupt line 0      */
  .word     FDCAN1_IT1_IRQHandler             /* FDCAN1 interrupt line 1      */
  .word     FDCAN2_IT1_IRQHandler             /* FDCAN2 interrupt line 1      */
  .word     EXTI9_5_IRQHandler                /* External Line[9:5]s          */
  .word     TIM1_BRK_IRQHandler               /* TIM1 Break interrupt         */
  .word     TIM1_UP_IRQHandler                /* TIM1 Update interrupt        */
  .word     TIM1_TRG_COM_IRQHandler           /* TIM1 Trigger and Commutation interrupt */
  .word     TIM1_CC_IRQHandler                /* TIM1 Capture Compare         */
  .word     TIM2_IRQHandler                   /* TIM2                         */
  .word     TIM3_IRQHandler                   /* TIM3                         */
  .word     TIM4_IRQHandler                   /* TIM4                         */
  .word     I2C1_EV_IRQHandler                /* I2C1 Event                   */
  .word     I2C1_ER_IRQHandler                /* I2C1 Error                   */
  .word     I2C2_EV_IRQHandler                /* I2C2 Event                   */
  .word     I2C2_ER_IRQHandler                /* I2C2 Error                   */
  .word     SPI1_IRQHandler                   /* SPI1                         */
  .word     SPI2_IRQHandler                   /* SPI2                         */
  .word     USART1_IRQHandler                 /* USART1                       */
  .word     USART2_IRQHandler                 /* USART2                       */
  .word     USART3_IRQHandler                 /* USART3                       */
  .word     EXTI15_10_IRQHandler              /* External Line[15:10]s        */
  .word     RTC_Alarm_IRQHandler              /* RTC Alarm (A and B) through EXTI Line */
  .word     0                                 /* Reserved                     */
  .word     TIM8_BRK_TIM12_IRQHandler         /* TIM8 Break and TIM12         */
  .word     TIM8_UP_TIM13_IRQHandler          /* TIM8 Update and TIM13        */
  .word     TIM8_TRG_COM_TIM14_IRQHandler     /* TIM8 Trigger and Commutation and TIM14 */
  .word     TIM8_CC_IRQHandler                /* TIM8 Capture Compare         */
  .word     DMA1_Stream7_IRQHandler           /* DMA1 Stream7                 */
  .word     FMC_IRQHandler                    /* FMC                          */
  .word     SDMMC1_IRQHandler                 /* SDMMC1                       */
  .word     TIM5_IRQHandler                   /* TIM5                         */
  .word     SPI3_IRQHandler                   /* SPI3                         */
  .word     UART4_IRQHandler                  /* UART4                        */
  .word     UART5_IRQHandler                  /* UART5                        */
  .word     TIM6_DAC_IRQHandler               /* TIM6 and DAC1&2 underrun errors */
  .word     TIM7_IRQHandler                   /* TIM7                         */
  .word     DMA2_Stream0_IRQHandler           /* DMA2 Stream 0                */
  .word     DMA2_Stream1_IRQHandler           /* DMA2 Stream 1                */
  .word     DMA2_Stream2_IRQHandler           /* DMA2 Stream 2                */
  .word     DMA2_Stream3_IRQHandler           /* DMA2 Stream 3                */
  .word     DMA2_Stream4_IRQHandler           /* DMA2 Stream 4                */
  .word     ETH_IRQHandler                    /* Ethernet                     */
  .word     ETH_WKUP_IRQHandler               /* Ethernet Wakeup through EXTI line */
  .word     FDCAN_CAL_IRQHandler              /* FDCAN calibration unit interrupt */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     DMA2_Stream5_IRQHandler           /* DMA2 Stream 5                */
  .word     DMA2_Stream6_IRQHandler           /* DMA2 Stream 6                */
  .word     DMA2_Stream7_IRQHandler           /* DMA2 Stream 7                */
  .word     USART6_IRQHandler                 /* USART6                       */
  .word     I2C3_EV_IRQHandler                /* I2C3 event                   */
  .word     I2C3_ER_IRQHandler                /* I2C3 error                   */
  .word     OTG_HS_EP1_OUT_IRQHandler         /* USB OTG HS End Point 1 Out   */
  .word     OTG_HS_EP1_IN_IRQHandler          /* USB OTG HS End Point 1 In    */
  .word     OTG_HS_WKUP_IRQHandler            /* USB OTG HS Wakeup through EXTI */
  .word     OTG_HS_IRQHandler                 /* USB OTG HS                   */
  .word     DCMI_PSSI_IRQHandler              /* DCMI, PSSI                   */
  .word     0                                 /* Reserved                     */
  .word     RNG_IRQHandler                    /* Rng                          */
  .word     FPU_IRQHandler                    /* FPU                          */
  .word     UART7_IRQHandler                  /* UART7                        */
  .word     UART8_IRQHandler                  /* UART8                        */
  .word     SPI4_IRQHandler                   /* SPI4                         */
  .word     SPI5_IRQHandler                   /* SPI5                         */
  .word     SPI6_IRQHandler                   /* SPI6                         */
  .word     SAI1_IRQHandler                   /* SAI1                         */
  .word     LTDC_IRQHandler                   /* LTDC                         */
  .word     LTDC_ER_IRQHandler                /* LTDC error                   */
  .word     DMA2D_IRQHandler                  /* DMA2D                        */
  .word     0                                 /* Reserved                     */
  .word     OCTOSPI1_IRQHandler               /* OCTOSPI1                     */
  .word     LPTIM1_IRQHandler                 /* LPTIM1                       */
  .word     CEC_IRQHandler                    /* HDMI_CEC                     */
  .word     I2C4_EV_IRQHandler                /* I2C4 Event                   */
  .word     I2C4_ER_IRQHandler                /* I2C4 Error                   */
  .word     SPDIF_RX_IRQHandler               /* SPDIF_RX                     */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     DMAMUX1_OVR_IRQHandler            /* DMAMUX1 Overrun interrupt    */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     DFSDM1_FLT0_IRQHandler            /* DFSDM Filter0 Interrupt      */
  .word     DFSDM1_FLT1_IRQHandler            /* DFSDM Filter1 Interrupt      */
  .word     DFSDM1_FLT2_IRQHandler            /* DFSDM Filter2 Interrupt      */
  .word     DFSDM1_FLT3_IRQHandler            /* DFSDM Filter3 Interrupt      */
  .word     0                                 /* Reserved                     */
  .word     SWPMI1_IRQHandler                 /* Serial Wire Interface 1 global interrupt */
  .word     TIM15_IRQHandler                  /* TIM15 global Interrupt       */
  .word     TIM16_IRQHandler                  /* TIM16 global Interrupt       */
  .word     TIM17_IRQHandler                  /* TIM17 global Interrupt       */
  .word     MDIOS_WKUP_IRQHandler             /* MDIOS Wakeup Interrupt       */
  .word     MDIOS_IRQHandler                  /* MDIOS global Interrupt       */
  .word     0                                 /* Reserved                     */
  .word     MDMA_IRQHandler                   /* MDMA global Interrupt        */
  .word     0                                 /* Reserved                     */
  .word     SDMMC2_IRQHandler                 /* SDMMC2 global Interrupt      */
  .word     HSEM1_IRQHandler                  /* HSEM1 global Interrupt       */
  .word     0                                 /* Reserved                     */
  .word     ADC3_IRQHandler                   /* ADC3 global Interrupt        */
  .word     DMAMUX2_OVR_IRQHandler            /* DMAMUX Overrun interrupt     */
  .word     BDMA_Channel0_IRQHandler          /* BDMA Channel 0 global Interrupt */
  .word     BDMA_Channel1_IRQHandler          /* BDMA Channel 1 global Interrupt */
  .word     BDMA_Channel2_IRQHandler          /* BDMA Channel 2 global Interrupt */
  .word     BDMA_Channel3_IRQHandler          /* BDMA Channel 3 global Interrupt */
  .word     BDMA_Channel4_IRQHandler          /* BDMA Channel 4 global Interrupt */
  .word     BDMA_Channel5_IRQHandler          /* BDMA Channel 5 global Interrupt */
  .word     BDMA_Channel6_IRQHandler          /* BDMA Channel 6 global Interrupt */
  .word     BDMA_Channel7_IRQHandler          /* BDMA Channel 7 global Interrupt */
  .word     COMP1_IRQHandler                  /* COMP1 global Interrupt       */
  .word     LPTIM2_IRQHandler                 /* LP TIM2 global interrupt     */
  .word     LPTIM3_IRQHandler                 /* LP TIM3 global interrupt     */
  .word     LPTIM4_IRQHandler                 /* LP TIM4 global interrupt     */
  .word     LPTIM5_IRQHandler                 /* LP TIM5 global interrupt     */
  .word     LPUART1_IRQHandler                /* LP UART1 interrupt           */
  .word     0                                 /* Reserved                     */
  .word     CRS_IRQHandler                    /* Clock Recovery Global Interrupt */
  .word     ECC_IRQHandler                    /* ECC diagnostic Global Interrupt */
  .word     SAI4_IRQHandler                   /* SAI4 global interrupt        */
  .word     DTS_IRQHandler                    /* Digital Temperature Sensor interrupt */
  .word     0                                 /* Reserved                     */
  .word     WAKEUP_PIN_IRQHandler             /* Interrupt for all 6 wake-up pins */
  .word     OCTOSPI2_IRQHandler               /* OCTOSPI2 Interrupt           */
  .word     0                                 /* Reserved                     */
  .word     0                                 /* Reserved                     */
  .word     FMAC_IRQHandler                   /* FMAC Interrupt               */
  .word     CORDIC_IRQHandler                 /* CORDIC Interrupt             */
  .word     UART9_IRQHandler                  /* UART9 Interrupt              */
  .word     USART10_IRQHandler                /* UART10 Interrupt             */
  .word     I2C5_EV_IRQHandler                /* I2C5 Event Interrupt         */
  .word     I2C5_ER_IRQHandler                /* I2C5 Error Interrupt         */
  .word     FDCAN3_IT0_IRQHandler             /* FDCAN3 interrupt line 0      */
  .word     FDCAN3_IT1_IRQHandler             /* FDCAN3 interrupt line 1      */
  .word     TIM23_IRQHandler                  /* TIM23 global interrupt       */
  .word     TIM24_IRQHandler                  /* TIM24 global interrupt       */

  .size  g_pfnVectors, .-g_pfnVectors

/*******************************************************************************
*
* Provide weak aliases for each Exception handler to the Default_Handler.
* As they are weak aliases, any function with the same name will override
* this definition.
*
*******************************************************************************/
  .weak      NMI_Handler
  .thumb_set NMI_Handler,Default_Handler

  .weak      HardFault_Handler
  .thumb_set HardFault_Handler,Default_Handler

  .weak      MemManage_Handler
  .thumb_set MemManage_Handler,Default_Handler

  .weak      BusFault_Handler
  .thumb_set BusFault_Handler,Default_Handler

  .weak      UsageFault_Handler
  .thumb_set UsageFault_Handler,Default_Handler

  .weak      SVC_Handler
  .thumb_set SVC_Handler,Default_Handler

  .weak      DebugMon_Handler
  .thumb_set DebugMon_Handler,Default_Handler

  .weak      PendSV_Handler
  .thumb_set PendSV_Handler,Default_Handler

  .weak      SysTick_Handler
  .thumb_set SysTick_Handler,Default_Handler

  .weak      WWDG_IRQHandler
  .thumb_set WWDG_IRQHandler,Default_Handler

  .weak      PVD_AVD_IRQHandler
  .thumb_set PVD_AVD_IRQHandler,Default_Handler

  .weak      TAMP_STAMP_IRQHandler
  .thumb_set TAMP_STAMP_IRQHandler,Default_Handler

  .weak      RTC_WKUP_IRQHandler
  .thumb_set RTC_WKUP_IRQHandler,Default_Handler

  .weak      FLASH_IRQHandler
  .thumb_set FLASH_IRQHandler,Default_Handler

  .weak      RCC_IRQHandler
  .thumb_set RCC_IRQHandler,Default_Handler

  .weak      EXTI0_IRQHandler
  .thumb_set EXTI0_IRQHandler,Default_Handler

  .weak      EXTI1_IRQHandler
  .thumb_set EXTI1_IRQHandler,Default_Handler

  .weak      EXTI2_IRQHandler
  .thumb_set EXTI2_IRQHandler,Default_Handler

  .weak      EXTI3_IRQHandler
  .thumb_set EXTI3_IRQHandler,Default_Handler

  .weak      EXTI4_IRQHandler
  .thumb_set EXTI4_IRQHandler,Default_Handler

  .weak      DMA1_Stream0_IRQHandler
  .thumb_set DMA1_Stream0_IRQHandler,Default_Handler

  .weak      DMA1_Stream1_IRQHandler
  .thumb_set DMA1_Stream1_IRQHandler,Default_Handler

  .weak      DMA1_Stream2_IRQHandler
  .thumb_set DMA1_Stream2_IRQHandler,Default_Handler

  .weak      DMA1_Stream3_IRQHandler
  .thumb_set DMA1_Stream3_IRQHandler,Default_Handler

  .weak      DMA1_Stream4_IRQHandler
  .thumb_set DMA1_Stream4_IRQHandler,Default_Handler

  .weak      DMA1_Stream5_IRQHandler
  .thumb_set DMA1_Stream5_IRQHandler,Default_Handler

  .weak      DMA1_Stream6_IRQHandler
  .thumb_set DMA1_Stream6_IRQHandler,Default_Handler

  .weak      ADC_IRQHandler
  .thumb_set ADC_IRQHandler,Default_Handler

  .weak      FDCAN1_IT0_IRQHandler
  .thumb_set FDCAN1_IT0_IRQHandler,Default_Handler

  .weak      FDCAN2_IT0_IRQHandler
  .thumb_set FDCAN2_IT0_IRQHandler,Default_Handler

  .weak      FDCAN1_IT1_IRQHandler
  .thumb_set FDCAN1_IT1_IRQHandler,Default_Handler

  .weak      FDCAN2_IT1_IRQHandler
  .thumb_set FDCAN2_IT1_IRQHandler,Default_Handler

  .weak      EXTI9_5_IRQHandler
  .thumb_set EXTI9_5_IRQHandler,Default_Handler

  .weak      TIM1_BRK_IRQHandler
  .thumb_set TIM1_BRK_IRQHandler,Default_Handler

  .weak      TIM1_UP_IRQHandler
  .thumb_set TIM1_UP_IRQHandler,Default_Handler

  .weak      TIM1_TRG_COM_IRQHandler
  .thumb_set TIM1_TRG_COM_IRQHandler,Default_Handler

  .weak      TIM1_CC_IRQHandler
  .thumb_set TIM1_CC_IRQHandler,Default_Handler

  .weak      TIM2_IRQHandler
  .thumb_set TIM2_IRQHandler,Default_Handler

  .weak      TIM3_IRQHandler
  .thumb_set TIM3_IRQHandler,Default_Handler

  .weak      TIM4_IRQHandler
  .thumb_set TIM4_IRQHandler,Default_Handler

  .weak      I2C1_EV_IRQHandler
  .thumb_set I2C1_EV_IRQHandler,Default_Handler

  .weak      I2C1_ER_IRQHandler
  .thumb_set I2C1_ER_IRQHandler,Default_Handler

  .weak      I2C2_EV_IRQHandler
  .thumb_set I2C2_EV_IRQHandler,Default_Handler

  .weak      I2C2_ER_IRQHandler
  .thumb_set I2C2_ER_IRQHandler,Default_Handler

  .weak      SPI1_IRQHandler
  .thumb_set SPI1_IRQHandler,Default_Handler

  .weak      SPI2_IRQHandler
  .thumb_set SPI2_IRQHandler,Default_Handler

  .weak      USART1_IRQHandler
  .thumb_set USART1_IRQHandler,Default_Handler

  .weak      USART2_IRQHandler
  .thumb_set USART2_IRQHandler,Default_Handler

  .weak      USART3_IRQHandler
  .thumb_set USART3_IRQHandler,Default_Handler

  .weak      EXTI15_10_IRQHandler
  .thumb_set EXTI15_10_IRQHandler,Default_Handler

  .weak      RTC_Alarm_IRQHandler
  .thumb_set RTC_Alarm_IRQHandler,Default_Handler

  .weak      TIM8_BRK_TIM12_IRQHandler
  .thumb_set TIM8_BRK_TIM12_IRQHandler,Default_Handler

  .weak      TIM8_UP_TIM13_IRQHandler
  .thumb_set TIM8_UP_TIM13_IRQHandler,Default_Handler

  .weak      TIM8_TRG_COM_TIM14_IRQHandler
  .thumb_set TIM8_TRG_COM_TIM14_IRQHandler,Default_Handler

  .weak      TIM8_CC_IRQHandler
  .thumb_set TIM8_CC_IRQHandler,Default_Handler

  .weak      DMA1_Stream7_IRQHandler
  .thumb_set DMA1_Stream7_IRQHandler,Default_Handler

  .weak      FMC_IRQHandler
  .thumb_set FMC_IRQHandler,Default_Handler

  .weak      SDMMC1_IRQHandler
  .thumb_set SDMMC1_IRQHandler,Default_Handler

  .weak      TIM5_IRQHandler
  .thumb_set TIM5_IRQHandler,Default_Handler

  .weak      SPI3_IRQHandler
  .thumb_set SPI3_IRQHandler,Default_Handler

  .weak      UART4_IRQHandler
  .thumb_set UART4_IRQHandler,Default_Handler

  .weak      UART5_IRQHandler
  .thumb_set UART5_IRQHandler,Default_Handler

  .weak      TIM6_DAC_IRQHandler
  .thumb_set TIM6_DAC_IRQHandler,Default_Handler

  .weak      TIM7_IRQHandler
  .thumb_set TIM7_IRQHandler,Default_Handler

  .weak      DMA2_Stream0_IRQHandler
  .thumb_set DMA2_Stream0_IRQHandler,Default_Handler

  .weak      DMA2_Stream1_IRQHandler
  .thumb_set DMA2_Stream1_IRQHandler,Default_Handler

  .weak      DMA2_Stream2_IRQHandler
  .thumb_set DMA2_Stream2_IRQHandler,Default_Handler

  .weak      DMA2_Stream3_IRQHandler
  .thumb_set DMA2_Stream3_IRQHandler,Default_Handler

  .weak      DMA2_Stream4_IRQHandler
  .thumb_set DMA2_Stream4_IRQHandler,Default_Handler

  .weak      ETH_IRQHandler
  .thumb_set ETH_IRQHandler,Default_Handler

  .weak      ETH_WKUP_IRQHandler
  .thumb_set ETH_WKUP_IRQHandler,Default_Handler

  .weak      FDCAN_CAL_IRQHandler
  .thumb_set FDCAN_CAL_IRQHandler,Default_Handler

  .weak      DMA2_Stream5_IRQHandler
  .thumb_set DMA2_Stream5_IRQHandler,Default_Handler

  .weak      DMA2_Stream6_IRQHandler
  .thumb_set DMA2_Stream6_IRQHandler,Default_Handler

  .weak      DMA2_Stream7_IRQHandler
  .thumb_set DMA2_Stream7_IRQHandler,Default_Handler

  .weak      USART6_IRQHandler
  .thumb_set USART6_IRQHandler,Default_Handler

  .weak      I2C3_EV_IRQHandler
  .thumb_set I2C3_EV_IRQHandler,Default_Handler

  .weak      I2C3_ER_IRQHandler
  .thumb_set I2C3_ER_IRQHandler,Default_Handler

  .weak      OTG_HS_EP1_OUT_IRQHandler
  .thumb_set OTG_HS_EP1_OUT_IRQHandler,Default_Handler

  .weak      OTG_HS_EP1_IN_IRQHandler
  .thumb_set OTG_HS_EP1_IN_IRQHandler,Default_Handler

  .weak      OTG_HS_WKUP_IRQHandler
  .thumb_set OTG_HS_WKUP_IRQHandler,Default_Handler

  .weak      OTG_HS_IRQHandler
  .thumb_set OTG_HS_IRQHandler,Default_Handler

  .weak      DCMI_PSSI_IRQHandler
  .thumb_set DCMI_PSSI_IRQHandler,Default_Handler

  .weak      RNG_IRQHandler
  .thumb_set RNG_IRQHandler,Default_Handler

  .weak      FPU_IRQHandler
  .thumb_set FPU_IRQHandler,Default_Handler

  .weak      UART7_IRQHandler
  .thumb_set UART7_IRQHandler,Default_Handler

  .weak      UART8_IRQHandler
  .thumb_set UART8_IRQHandler,Default_Handler

  .weak      SPI4_IRQHandler
  .thumb_set SPI4_IRQHandler,Default_Handler

  .weak      SPI5_IRQHandler
  .thumb_set SPI5_IRQHandler,Default_Handler

  .weak      SPI6_IRQHandler
  .thumb_set SPI6_IRQHandler,Default_Handler

  .weak      SAI1_IRQHandler
  .thumb_set SAI1_IRQHandler,Default_Handler

  .weak      LTDC_IRQHandler
  .thumb_set LTDC_IRQHandler,Default_Handler

  .weak      LTDC_ER_IRQHandler
  .thumb_set LTDC_ER_IRQHandler,Default_Handler

  .weak      DMA2D_IRQHandler
  .thumb_set DMA2D_IRQHandler,Default_Handler

  .weak      OCTOSPI1_IRQHandler
  .thumb_set OCTOSPI1_IRQHandler,Default_Handler

  .weak      LPTIM1_IRQHandler
  .thumb_set LPTIM1_IRQHandler,Default_Handler

  .weak      CEC_IRQHandler
  .thumb_set CEC_IRQHandler,Default_Handler

  .weak      I2C4_EV_IRQHandler
  .thumb_set I2C4_EV_IRQHandler,Default_Handler

  .weak      I2C4_ER_IRQHandler
  .thumb_set I2C4_ER_IRQHandler,Default_Handler

  .weak      SPDIF_RX_IRQHandler
  .thumb_set SPDIF_RX_IRQHandler,Default_Handler

  .weak      DMAMUX1_OVR_IRQHandler
  .thumb_set DMAMUX1_OVR_IRQHandler,Default_Handler

  .weak      DFSDM1_FLT0_IRQHandler
  .thumb_set DFSDM1_FLT0_IRQHandler,Default_Handler

  .weak      DFSDM1_FLT1_IRQHandler
  .thumb_set DFSDM1_FLT1_IRQHandler,Default_Handler

  .weak      DFSDM1_FLT2_IRQHandler
  .thumb_set DFSDM1_FLT2_IRQHandler,Default_Handler

  .weak      DFSDM1_FLT3_IRQHandler
  .thumb_set DFSDM1_FLT3_IRQHandler,Default_Handler

  .weak      SWPMI1_IRQHandler
  .thumb_set SWPMI1_IRQHandler,Default_Handler

  .weak      TIM15_IRQHandler
  .thumb_set TIM15_IRQHandler,Default_Handler

  .weak      TIM16_IRQHandler
  .thumb_set TIM16_IRQHandler,Default_Handler

  .weak      TIM17_IRQHandler
  .thumb_set TIM17_IRQHandler,Default_Handler

  .weak      MDIOS_WKUP_IRQHandler
  .thumb_set MDIOS_WKUP_IRQHandler,Default_Handler

  .weak      MDIOS_IRQHandler
  .thumb_set MDIOS_IRQHandler,Default_Handler

  .weak      MDMA_IRQHandler
  .thumb_set MDMA_IRQHandler,Default_Handler

  .weak      SDMMC2_IRQHandler
  .thumb_set SDMMC2_IRQHandler,Default_Handler

  .weak      HSEM1_IRQHandler
  .thumb_set HSEM1_IRQHandler,Default_Handler

  .weak      ADC3_IRQHandler
  .thumb_set ADC3_IRQHandler,Default_Handler

  .weak      DMAMUX2_OVR_IRQHandler
  .thumb_set DMAMUX2_OVR_IRQHandler,Default_Handler

  .weak      BDMA_Channel0_IRQHandler
  .thumb_set BDMA_Channel0_IRQHandler,Default_Handler

  .weak      BDMA_Channel1_IRQHandler
  .thumb_set BDMA_Channel1_IRQHandler,Default_Handler

  .weak      BDMA_Channel2_IRQHandler
  .thumb_set BDMA_Channel2_IRQHandler,Default_Handler

  .weak      BDMA_Channel3_IRQHandler
  .thumb_set BDMA_Channel3_IRQHandler,Default_Handler

  .weak      BDMA_Channel4_IRQHandler
  .thumb_set BDMA_Channel4_IRQHandler,Default_Handler

  .weak      BDMA_Channel5_IRQHandler
  .thumb_set BDMA_Channel5_IRQHandler,Default_Handler

  .weak      BDMA_Channel6_IRQHandler
  .thumb_set BDMA_Channel6_IRQHandler,Default_Handler

  .weak      BDMA_Channel7_IRQHandler
  .thumb_set BDMA_Channel7_IRQHandler,Default_Handler

  .weak      COMP1_IRQHandler
  .thumb_set COMP1_IRQHandler,Default_Handler

  .weak      LPTIM2_IRQHandler
  .thumb_set LPTIM2_IRQHandler,Default_Handler

  .weak      LPTIM3_IRQHandler
  .thumb_set LPTIM3_IRQHandler,Default_Handler

  .weak      LPTIM4_IRQHandler
  .thumb_set LPTIM4_IRQHandler,Default_Handler

  .weak      LPTIM5_IRQHandler
  .thumb_set LPTIM5_IRQHandler,Default_Handler

  .weak      LPUART1_IRQHandler
  .thumb_set LPUART1_IRQHandler,Default_Handler

  .weak      CRS_IRQHandler
  .thumb_set CRS_IRQHandler,Default_Handler

  .weak      ECC_IRQHandler
  .thumb_set ECC_IRQHandler,Default_Handler

  .weak      SAI4_IRQHandler
  .thumb_set SAI4_IRQHandler,Default_Handler

  .weak      DTS_IRQHandler
  .thumb_set DTS_IRQHandler,Default_Handler

  .weak      WAKEUP_PIN_IRQHandler
  .thumb_set WAKEUP_PIN_IRQHandler,Default_Handler

  .weak      OCTOSPI2_IRQHandler
  .thumb_set OCTOSPI2_IRQHandler,Default_Handler

  .weak      FMAC_IRQHandler
  .thumb_set FMAC_IRQHandler,Default_Handler

  .weak      CORDIC_IRQHandler
  .thumb_set CORDIC_IRQHandler,Default_Handler

  .weak      UART9_IRQHandler
  .thumb_set UART9_IRQHandler,Default_Handler

  .weak      USART10_IRQHandler
  .thumb_set USART10_IRQHandler,Default_Handler

  .weak      I2C5_EV_IRQHandler
  .thumb_set I2C5_EV_IRQHandler,Default_Handler

  .weak      I2C5_ER_IRQHandler
  .thumb_set I2C5_ER_IRQHandler,Default_Handler

  .weak      FDCAN3_IT0_IRQHandler
  .thumb_set FDCAN3_IT0_IRQHandler,Default_Handler

  .weak      FDCAN3_IT1_IRQHandler
  .thumb_set FDCAN3_IT1_IRQHandler,Default_Handler

  .weak      TIM23_IRQHandler
  .thumb_set TIM23_IRQHandler,Default_Handler

  .weak      TIM24_IRQHandler
  .thumb_set TIM24_IRQHandler,Default_Handler
