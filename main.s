;****************** main.s ***************
; Program written by: Ryan Kim
; Date Created: 2/4/2017
; Last Modified: 1/15/2018
; Brief description of the program
;   The LED toggles at 8 Hz and a varying duty-cycle
; Hardware connections (External: One button and one LED)
;  PE1 is Button input  (1 means pressed, 0 means not pressed)
;  PE0 is LED output (1 activates external LED on protoboard)
;  PF4 is builtin button SW1 on Launchpad (Internal) 
;        Negative Logic (0 means pressed, 1 means not pressed)
; Overall functionality of this system is to operate like this
;   1) Make PE0 an output and make PE1 and PF4 inputs.
;   2) The system starts with the the LED toggling at 8Hz,
;      which is 8 times per second with a duty-cycle of 20%.
;      Therefore, the LED is ON for (0.2*1/8)th of a second
;      and OFF for (0.8*1/8)th of a second.
;   3) When the button on (PE1) is pressed-and-released increase
;      the duty cycle by 20% (modulo 100%). Therefore for each
;      press-and-release the duty cycle changes from 20% to 40% to 60%
;      to 80% to 100%(ON) to 0%(Off) to 20% to 40% so on
;   4) Implement a "breathing LED" when SW1 (PF4) on the Launchpad is pressed:
;      a) Be creative and play around with what "breathing" means.
;         An example of "breathing" is most computers power LED in sleep mode
;         (e.g., https://www.youtube.com/watch?v=ZT6siXyIjvQ).
;      b) When (PF4) is released while in breathing mode, resume blinking at 8Hz.
;         The duty cycle can either match the most recent duty-
;         cycle or reset to 20%.
;      TIP: debugging the breathing LED algorithm and feel on the simulator is impossible.
; PortE device registers
GPIO_PORTE_DATA_R  EQU 0x400243FC
GPIO_PORTE_DIR_R   EQU 0x40024400
GPIO_PORTE_AFSEL_R EQU 0x40024420
GPIO_PORTE_DEN_R   EQU 0x4002451C
; PortF device registers
GPIO_PORTF_DATA_R  EQU 0x400253FC
GPIO_PORTF_DIR_R   EQU 0x40025400
GPIO_PORTF_AFSEL_R EQU 0x40025420
GPIO_PORTF_PUR_R   EQU 0x40025510
GPIO_PORTF_DEN_R   EQU 0x4002551C
GPIO_PORTF_LOCK_R  EQU 0x40025520
GPIO_PORTF_CR_R    EQU 0x40025524
GPIO_LOCK_KEY      EQU 0x4C4F434B  ; Unlocks the GPIO_CR register
SYSCTL_RCGCGPIO_R  EQU 0x400FE608

     IMPORT  TExaS_Init
     THUMB
     AREA    DATA, ALIGN=2
;global variables go here
	
     AREA    |.text|, CODE, READONLY, ALIGN=2
     THUMB
     EXPORT  Start
Start
 ; TExaS_Init sets bus clock at 80 MHz
     BL  TExaS_Init ; voltmeter, scope on PD3
 ; Initialization goes here
 ;
 ;Port E Initialization
	LDR	R1, =SYSCTL_RCGCGPIO_R		
	LDR	R0, [R1]					
	ORR	R0, #0x30					
	STR	R0, [R1]					;turns clock on for ports E and F
	NOP
	NOP
	NOP
	NOP								;wait for clock to stabilize
	LDR	R1, =GPIO_PORTE_DIR_R		
	MOV	R0, #0x01					
	STR	R0, [R1]					;PE0 is output
	LDR	R1, =GPIO_PORTE_DEN_R		
	MOV	R0, #0x03					
	STR	R0, [R1]					;enable digital logic for PE0,1
	;Port F Initialization
	LDR	R1, =GPIO_PORTF_LOCK_R		
	LDR	R0, =GPIO_LOCK_KEY			
	STR	R0, [R1]					;unlocks port F
	LDR	R1, =GPIO_PORTF_CR_R		
	MOV	R0, #0xFF					
	STR	R0, [R1]					;allow access
	LDR	R1, =GPIO_PORTF_DIR_R		
	MOV	R0, #0x00					
	STR	R0, [R1]					;no outputs for PF
	LDR	R1, =GPIO_PORTF_PUR_R		
	MOV	R0, #0x10					
	STR	R0, [R1]					;enable negative logic for PF4
	LDR	R1, =GPIO_PORTF_DEN_R		
	MOV	R0, #0x10					
	STR	R0, [R1]					;enable digital logic for PE4	
	;global variables
	MOV	R3, #0						;R3=0~5
	MOV	R4, #5						;R4=5 always
	MOV	R5, #0						;R5 is status register: 0=ready 1=not ready
	MOV	R7, #10						;R7=10 always (used in BREATHING function)
	MOV	R9, #0						;counter for BREATHING (reinitialized every loop)
     CPSIE  I    ; TExaS voltmeter, scope runs on interrupts
loop  
; main engine goes here
	BL		DUTY_SHIFT				;increase duty
WAIT_1
;
	LDR		R1, =GPIO_PORTF_DATA_R
	LDR		R0, [R1]				
	BIC		R0, #0xEF				;clear everything but input
	LSR		R0, #4					;LSB contains input
	ADDS	R0, #0					;set flag=input
	BEQ		BREATHING				;if PF4 pressed, call BREATHING function
;
MAIN
	MOV		R1, #1					
	BL		LED_DISPLAY				;turn on LED
	MOV		R1, R3					
	BL		DELAY					;wait for R3*25ms
;
	MOV		R1, #0					
	BL		LED_DISPLAY				;turn off LED
	SUBS	R1, R4, R3				
	BL		DELAY					;wait for (5-R3)*25ms	
;
	ADDS	R5, #0					;set flag=R5
	BEQ		READY_TO_READ
;
;	Works likes a flip-flop
	LDR		R1, =GPIO_PORTE_DATA_R
	LDR		R0, [R1]				
	BIC		R0, #0xFD				;clear all bits but input
	LSR		R0, #1					
	ADDS	R0, #0					;set flag=input
	BNE		WAIT_1					
	BIC		R5, #0x01				;toggled to "ready to read" once PE1 is unpressed
	B		WAIT_1
;
READY_TO_READ
	LDR		R1, =GPIO_PORTE_DATA_R
	LDR		R0, [R1]				
	BIC		R0, #0xFD				;clear all bits but input
	LSR		R0, #1					
	ADDS	R0, #0					;set flag=input
	BEQ		WAIT_1					
	ORR		R5, #0x01				;ups duty cycle, not ready to read
	B		loop					
;
BREATHING
;called upon when PF4=0, exited when PF4=1
;Input: none
;Output: none
	;local variables
	MOV		R6, #0					;reset R6
	MOV		R8, #0					;R8: increasing=0, decreasing=1
	;
AGAIN_5
	BL		BREATHING_DUTY_SHIFT	;change duty cycle
	MOV		R9, #8
AGAIN_4
	LDR		R1, =GPIO_PORTF_DATA_R
	LDR		R0, [R1]
	BIC		R0, #0xEF
	LSR		R0, #4
	ADDS	R0, #0
	BNE		RETURN_TO_MAIN			;check if PF4 is unpressed every loop
;
	MOV		R1, #1
	BL		LED_DISPLAY
	MOV		R1, R6
	BL		BREATHING_DELAY			;turn on LED for R6 number of cycles
;
	MOV		R1, #0
	BL		LED_DISPLAY
	SUBS	R1, R7, R6
	BL		BREATHING_DELAY			;turn off LED for (10-R6) number of cycles
;
	SUBS	R9, #1
	BNE		AGAIN_4					;loop if 8 times
	B		AGAIN_5					;loop and change duty cycle
;
RETURN_TO_MAIN
	B		MAIN

;**********************************************************************
;**********************************************************************
;***************************Subroutines********************************
;**********************************************************************
;**********************************************************************

LED_DISPLAY
;turns LED on or off
;Input: R1: 0=off 1=on
;Output: none
	LDR		R2, =GPIO_PORTE_DATA_R		
	LDR		R0, [R2]				;reads input
	BIC		R0, #0xFF
	ORR		R0, R1					;LED = switch value
	STR		R0, [R2]
	BX		LR						;return to main program

;
DELAY
;runs nothing for 0.2*0.125=1s/40=25ms
;Input:	R1=number of 25ms intervals/cycle
;Output: none
	ADDS	R1, #0
	BEQ		DELAY_DONE				;no delay if 0%/100% duty
	MOV		R0, #20					;20*4*25000/80MHz=25ms
AGAIN_2
	MOV		R2, #25000
WAIT_2
	SUBS	R2, #1
	BNE		WAIT_2
	SUBS	R0, #1
	BNE		AGAIN_2
	SUBS	R1, #1
	BNE		DELAY
DELAY_DONE
	BX		LR
	
;
DUTY_SHIFT
;Increase duty cycle by 20% mod 100%
;Input: R3
;Output: increment R3, reducing if needed
	SUBS	R3, #5
	BEQ		MOD_DONE				;checks if equal R3 is to 5
	ADDS	R3, #6					;restores if not
MOD_DONE
	BX		LR
	
;
BREATHING_DELAY
;runs nothing for 1.25ms R1 number of times
;Input: R1=number of 12.5ms intervals/cycle
;Output: none
	ADDS	R1, #0
	BEQ		BREATHING_DELAY_DONE	;no delay if 0%/100% duty
	MOV		R0, #10					;10*4*2500/80MHz=1.25ms
AGAIN_3
	MOV		R2, #2500
WAIT_3
	SUBS	R2, #1
	BNE		WAIT_3
	SUBS	R0, #1
	BNE		AGAIN_3
	SUBS	R1, #1
	BNE		BREATHING_DELAY
BREATHING_DELAY_DONE
	BX		LR
	
;
BREATHING_DUTY_SHIFT
;increment/decrement R6, changing monotonicity at 0% and 100% duty
;Input: R6,8
;Output: increment or decrement R6, toggle LSB[R8]
	ADDS	R8, #0					;set flag=R8
	BNE		DECREASING				;R8=1 means monotonically decreasing
	SUBS	R6, #10
	BEQ		RESTORE_FIRST		;change mono if R6=10
	ADDS	R6, #11					;increment
B_DUTY_DONE
	BX		LR						;return
DECREASING
	ADDS	R6, #0					;set flag=R6
	BEQ		CHANGE_MONOTONICITY		;change mono if R6=0
	SUBS	R6, #1					;decrement R6
	B		B_DUTY_DONE
CHANGE_MONOTONICITY
	EOR		R8, #0x01				;toggle R8
	B		BREATHING_DUTY_SHIFT
RESTORE_FIRST
	ADDS	R6, #10					
	B		CHANGE_MONOTONICITY
;
     ALIGN      ; make sure the end of this section is aligned
     END        ; end of file

