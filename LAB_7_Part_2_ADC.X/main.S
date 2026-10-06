    ; Luke Groesbeck
    ; RCET3373
    ; Timers
    ; https://github.com/groeluke/LAB_7_ADC/tree/main/LAB_7_Part_2_ADC.X
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
   DelayCount  EQU 0x70   ;countdown used inside Delay100us
   Index       EQU 0x71   ;position 0-20, then reused as the pulse countdown
; Reset Vector at 0000h. Execution starts here after reset.
PSECT resetVect,class=CODE,delta=2
ResetVector: 
    GOTO Setup

; Interrupt Vector at 0004h. Execution starts here after an interrupt.
PSECT isrVect,class=CODE,delta=2
InterruptVector:
   
; Main code section starts at 0008h. User code goes here.
PSECT code,class=CODE,delta=2
 
Setup: 
 ;          Bank 1
    BANKSEL TRISA
    BSF     TRISA,0       ;RA0 is an input - this is where the pot wiper connects
    BCF     TRISA,1       ;RA1 is an output - this is the wire that goes to the servo

    BCF     ADCON1,7      ;left justified results this time
    BCF     ADCON1,4      ;top of the ADC's measuring range = VDD
    BCF     ADCON1,5      ;bottom of the ADC's measuring range = VSS (ground)

    ;          Bank 3
    BANKSEL ANSEL
    BSF     ANSEL,0       ;set RA0 is a analog input pin
    BCF     ANSEL,1       ;set RA1 as a digital I/O pin
    CLRF    ANSELH

    ;          Bank 0
    BANKSEL ADCON0
    BCF     ADCON0,7      ;pick the ADCs internal speed
    BSF     ADCON0,6      ;Fosc/8,
    CLRF    ADRESH
    CLRF    ADRESL
    CLRF    PORTA         ;make sure nothing is on port a
    BSF     ADCON0,0      ;turn the ADC module on

    MOVLW   0xF6
    MOVWF   TMR1H         ;load the timer's starting count, high byte
    MOVLW   0x3C
    MOVWF   TMR1L         ;low byte, so it takes exactly 20ms to roll over
    BCF     PIR1,0        ;make sure the timer's flag starts out clean

    BANKSEL PIE1
    BCF     PIE1,0        ;let Timer1 actually trigger an interrupt when it rolls over

    BANKSEL T1CON
    MOVLW   0b00110001    ;prescale 1:8, use the chip's own clock, and start the timer
    MOVWF   T1CON
    
    BCF     PIR1,0        ;clear Timer1 overflow interrupt flag bit

Main:
    BANKSEL PIR1
    BTFSS   PIR1,0        ;has Timer1 overflow happened
    GOTO    Main          ;no keep checking, do nothing else
    BCF     PIR1,0        ;yes handle it and run program
    
    ;      Reload Timer1 for the next 20ms delay set
    BANKSEL TMR1H
    MOVLW   0xF6
    MOVWF   TMR1H
    MOVLW   0x3C
    MOVWF   TMR1L

    NOP                   ;short pause so the ADC can settle on the
    NOP                   ;pot's voltage before we lock it in
    NOP
    NOP
    NOP
    
    BSF     ADCON0,1      ;turn on A/D conversion status bit 
Conversion:
    BTFSC   ADCON0,1      ;keep checking until it clears itself when done
    GOTO    Conversion    ;

    CLRF    Index         ;clear index to zero for the next section
IndexLoop:
    MOVLW   12            ;move 12 to be subtracted from 255
    SUBWF   ADRESH,F      ;subtracte 12 from ADRESH until 0 or negitive value
    BTFSS   STATUS,0      ;did ADRESH go negitive? yes then GOTO IndexDone
    GOTO    IndexDone     ;indexdone checks to see if the index is in a valid range
    INCF    Index,F       ;if still a positive count then increment index until 0
    GOTO    IndexLoop     ;stay in the loop until the count is zero or negitve 

IndexDone:
    MOVLW   20            ;checks to make sure in desired range
    SUBWF   Index,W       ;W = Index - 20
    BTFSS   STATUS,0      ;Carry = 0 if Index is less than 20
    GOTO    MakePulse     ;Index is 0-19, so keep it
    MOVLW   20            ;20 is the max limit of index count
    MOVWF   Index         ;Index was 20 or 21, so limit it to 20

;         turn the position number into an actual pulse
MakePulse:
    MOVLW   5             ;5 will be added to index
    ADDWF   Index,F       ;Index is how many 100us for PWM

    BSF     PORTA,1       ;start the pulse RA1 goes HIGH here

PulseLoop:
    CALL    Delay         ;call the delay section for a 100us delay
    DECFSZ  Index,F       ;do the delay the Index amount of times
    GOTO    PulseLoop     ;keeps going until index is zero
    BCF     PORTA,1       ;once zero set RA1 low 
    GOTO    Main          ;return

; Delay100us: hand-timed, instruction by instruction, to take
; exactly 100 cycles to run - and since 1 cycle = 1us on this chip
Delay:
    MOVLW   30            ;run the DelayCount 30 times which is 89 Tcy @ 1us
    MOVWF   DelayCount    ;move 30 into DelayCount
    NOP                   ;1 Tcy
    NOP                   ;1 Tcy

DelayLoop:
    DECFSZ  DelayCount,F  ;Decrement from 30 until zero for the delay
    GOTO    DelayLoop     ;keeps looping until DelayCount is zero
    RETURN                ;Return to PulseLoop 

    End