    ; Luke Groesbeck
    ; RCET3373
    ; Timers
    ; https://github.com/groeluke/LAB_7_ADC/tree/main/LAB_7_Part_3_ADC.X
    ; Linker code = -Wl,-presetVect=0000h,-pisrVect=0004h,-pcode=0008h
    
; PIC16F883 Configuration Bit Settings

; Assembly source line config statements

; CONFIG1
  CONFIG  FOSC = XT             ; Oscillator Selection bits (XT oscillator: Crystal/resonator on RA6/OSC2/CLKOUT and RA7/OSC1/CLKIN)
  CONFIG  WDTE = OFF            ; Watchdog Timer Enable bit (WDT disabled and can be enabled by SWDTEN bit of the WDTCON register)
  CONFIG  PWRTE = OFF           ; Power-up Timer Enable bit (PWRT disabled)
  CONFIG  MCLRE = ON            ; RE3/MCLR pin function select bit (RE3/MCLR pin function is MCLR)
  CONFIG  CP = OFF              ; Code Protection bit (Program memory code protection is disabled)
  CONFIG  CPD = OFF             ; Data Code Protection bit (Data memory code protection is disabled)
  CONFIG  BOREN = OFF           ; Brown Out Reset Selection bits (BOR disabled)
  CONFIG  IESO = OFF            ; Internal External Switchover bit (Internal/External Switchover mode is disabled)
  CONFIG  FCMEN = OFF           ; Fail-Safe Clock Monitor Enabled bit (Fail-Safe Clock Monitor is disabled)
  CONFIG  LVP = OFF             ; Low Voltage Programming Enable bit (RB3 pin has digital I/O, HV on MCLR must be used for programming)

; CONFIG2
  CONFIG  BOR4V = BOR40V        ; Brown-out Reset Selection bit (Brown-out Reset set to 4.0V)
  CONFIG  WRT = OFF             ; Flash Program Memory Self Write Enable bits (Write protection off)

; config statements should precede project file includes.
#include <xc.inc>
   ccp_next_l  EQU 0x23   ;lookup module writes the answer here (low byte)
   ccp_next_h  EQU 0x24   ;...and here (high byte) - 0x25 is reserved, don't touch it

   GLOBAL  ccp_next_l, ccp_next_h
   EXTRN   LookupAdc6ToCcp

   W_TEMP      EQU 0x70   ;save W during the ISR
   STATUS_TEMP EQU 0x71   ;save STATUS during the ISR
   Pulse       EQU 0x72   ;bit0: 1 while the servo pulse is actively HIGH
   ADCDone     EQU 0x73   ;bit0: 1 once this frame's NEXT value is ready
   ADCIndex    EQU 0x74   ;the ADC reading, squeezed down to 0-63
    
; Reset Vector at 0000h. Execution starts here after reset.
PSECT resetVect,class=CODE,delta=2
ResetVector: 
    GOTO Setup

; Interrupt Vector at 0004h. Execution starts here after an interrupt.
PSECT isrVect,class=CODE,delta=2
InterruptVector:
    GOTO    IsrHandler
   
; Main code section starts at 0008h. User code goes here.
PSECT code,class=CODE,delta=2
 
Setup: 
    ;       Bank 3
    BANKSEL ANSEL
    BSF     ANSEL,0       ;set RA0 is a analog input pin
    CLRF    ANSELH
 ;          Bank 1
    BANKSEL TRISA
    BSF     TRISA,0       ;RA0 is an input - this is where the pot wiper connects
    BCF     TRISC,2       ;RC2 is an output to the servo for control
    BCF     ADCON1,7      ;left justified
    BCF     ADCON1,4      ;top of the ADC's measuring range VDD
    BCF     ADCON1,5      ;bottom of the ADC's measuring range VSS (ground)
    ;       Bank 0
    BANKSEL ADCON0
    BCF     ADCON0,7      ;pick the ADCs internal speed
    BSF     ADCON0,6      ;Fosc/8
    CLRF    ADRESH
    CLRF    ADRESL
    BSF     ADCON0,0      ;turn the ADC module on
    MOVLW   0b00001010    ;CCP1 in Compare mode: just flag an interrupt on
    MOVWF   CCP1CON       ;match, don't touch the pin directly ourselves
    MOVLW   0xB1
    MOVWF   TMR1H         ;load the timer's starting count, high byte
    MOVLW   0xE0
    MOVWF   TMR1L         ;low byte, so it takes exactly 20ms to roll over
    BCF     PORTC,2       ;set the servo low so no weird glitch
    BCF     PIR1,0        ;clear the timer1 interrupt flag
    BCF     PIR1,2        ;clear the CCP1 interrupt flag 
    BANKSEL PIE1
    BSF     PIE1,0        ;Timer1 CAN now trigger an interrupt when it rolls over
    BSF     PIE1,2        ;CCP1 can now trigger an interrupt on a compare match
    BANKSEL ADCON0        ; back to Bank 0
    CLRF    Pulse         ;nothing is happening yet
    CLRF    ADCDone
    
    ;before Timer1 ever starts,
    ;so the very first frame has a real value to use instead
    ;of garbage
    BSF     ADCON0,1

StartupWait:
    BTFSC   ADCON0,1
    GOTO    $-1
    MOVF    ADRESH,W
    MOVWF   ADCIndex
    BCF     STATUS,0
    RRF     ADCIndex,F    ;shift right once RRF rotates f right throught a carry flag
    BCF     STATUS,0
    RRF     ADCIndex,F    ;again so ADCIndex is now a clean 0-63 number
    MOVF    ADCIndex,W
    PAGESEL LookupAdc6ToCcp  ;the lookup routine might live on a different
    CALL    LookupAdc6ToCcp  ;page of program memory, so this makes sure
    PAGESEL $             ;the CALL actually lands on it
    MOVF    ccp_next_h,W
    MOVWF   CCPR1H        ;manually load the very first pulse's end-time,
    MOVF    ccp_next_l,W  ;since Timer1's ISR (which normally does this)
    MOVWF   CCPR1L        ;hasn't run yet
    BSF     ADCDone,0     ;this value is ready and waiting
    MOVLW   0b00000001    ;prescale 1:1, internal clock, and start Timer1
    MOVWF   T1CON         ;counting right now, from 0xB1E0
    BSF     INTCON,6      ;allow peripherals to interrupt at all
    BSF     INTCON,7      ;interrupts can now actually happen
Main:
    BTFSC   Pulse,0       ;is a pulse still actively running
    GOTO    Main          ;if high don't touch the ADC yet
    BTFSC   ADCDone,0     ;have we already prepared next frame's value
    GOTO    Main          ;if high then nothing more to do until the next frame

    BSF     ADCON0,1
ConvWait:
    BTFSC   ADCON0,1
    GOTO    ConvWait
    MOVF    ADRESH,W
    MOVWF   ADCIndex
    BCF     STATUS,0
    RRF     ADCIndex,F
    BCF     STATUS,0
    RRF     ADCIndex,F    ;AdcIndex is now 0-63
    MOVF    ADCIndex,W
    PAGESEL LookupAdc6ToCcp
    CALL    LookupAdc6ToCcp  ;ccp_next_h:ccp_next_l now holds next
    PAGESEL $                ;frame's pulse end-time
    BSF     ADCDone,0     ;done for this frame - go idle
    GOTO    Main
; ISR - Timer1 starts each frame's pulse, CCP1 ends it. Nothing else
; in this program can interrupt, so either one could have fired.
IsrHandler:
    MOVWF   W_TEMP
    SWAPF   STATUS,W
    MOVWF   STATUS_TEMP
    BTFSC   PIR1,0        ;did Timer1 just roll over? (new frame)
    CALL    Service_Timer1
    BTFSC   PIR1,2        ;did CCP1 just match? (pulse should end)
    CALL    Service_CCP1
    SWAPF   STATUS_TEMP,W
    MOVWF   STATUS
    SWAPF   W_TEMP,F
    SWAPF   W_TEMP,W
    RETFIE

; Service_Timer1: a new 20ms frame has begun. Start the pulse,
; tell CCP1 when to end it, and clear the way for main to start
; preparing the NEXT frame's value.

Service_Timer1:
    BCF     PIR1,0        ;clear the flag
    MOVLW   0xB1
    MOVWF   TMR1H         ;reload the same starting count
    MOVLW   0xE0
    MOVWF   TMR1L         ;so every frame is exactly 20ms

    BSF     PORTC,2       ;pulse starts now - servo pin goes HIGH

    MOVF    ccp_next_h,W
    MOVWF   CCPR1H        ;tell CCP1 the exact Timer1 count that
    MOVF    ccp_next_l,W  ;should end THIS pulse (calculated last frame)
    MOVWF   CCPR1L

    BCF     ADCDone,0     ;main is now free to prepare next frame's value
    BSF     Pulse,0       ;and main must NOT touch the ADC until this clears
    RETURN

; Service_CCP1: Timer1's count just reached the target we loaded -
; this pulse is over.

Service_CCP1:
    BCF     PIR1,2        ;clear the flag
    BCF     PORTC,2       ;pulse ends now - servo pin goes LOW
    BCF     Pulse,0       ;main is now allowed to work again
    RETURN
    
    End