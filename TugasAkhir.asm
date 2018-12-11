;====================================================================
; A BLOCK RACER GAME 
; Processor		: ATmega8515
; Compiler		: AVRASM
;====================================================================

;====================================================================
; DEFINITIONS
;====================================================================

.include "m8515def.inc"

.def temp = r16 ; temporary register
.def temp2 = r17
.def seed = r18
.def obs_det = r19
.def position = r20
.def score = r21
.def state = r22
.def EW = r23 ; for PORTA
.def PB = r24 ; for PORTB
.def A  = r25 

.equ SRAM_ARRAY_POINTER = $60
.equ SRAM_SCORE_POINTER = $A6
.equ BLOCK = 0x23
.equ BLANK = 0x20
.equ CHAR = 0x58
.equ TIMER_COUNTER_POINTER = $C0
;====================================================================
; RESET and INTERRUPT VECTORS
;====================================================================

.org $00
rjmp MAIN
.org $01
rjmp START_BUTTON
.org $02
rjmp UP_BUTTON
.org $0D
rjmp DOWN_BUTTON
.org $0E
rjmp ISR_TCOM0

;====================================================================
; CODE SEGMENT (MAIN)
;====================================================================

MAIN:

INIT_STACK:
	ldi temp, low(RAMEND)
	out SPL, temp
	ldi temp, high(RAMEND) 
	out SPH, temp

INIT_STARTER:
	ldi obs_det, 0
	ldi seed, 0
	ldi state, 0
	ldi position, 0
	ldi XH, 3
	ser temp
	sts TIMER_COUNTER_POINTER, temp
	rjmp INIT_SCORE
	
INIT_TIMER:
	ldi temp2, 0
	ldi temp, 1<<CS02 ; 
	out TCCR0,temp			
	ldi temp,1<<OCF0
	out TIFR,temp		; Interrupt if compare true in T/C0
	ldi temp,1<<OCIE0
	out TIMSK,temp		; Enable Timer/Counter0 compare int
	ldi YH, high(TIMER_COUNTER_POINTER)
	ldi YL, low(TIMER_COUNTER_POINTER)
	ld temp, Y
	ldi temp, 0x0F
	out OCR0,temp		; Set compared value
	ser temp
	out DDRB, temp
	ret

INIT_SCORE:
	ldi temp, 7
	ldi ZH, high(SRAM_ARRAY_POINTER)
	ldi ZL, SRAM_SCORE_POINTER	
	SCORE_LOOP:
	tst temp
	breq DONE_SCORE_LOOP
	ldi temp2, 0x30
	st Z, temp2
	subi ZL, 1
	dec temp
	rjmp SCORE_LOOP
	DONE_SCORE_LOOP:

rcall INIT_ALLOCATE_BOARD	
rcall INIT_INTERRUPT
rcall INIT_LED
rcall INIT_LCD_MAIN

sei
rjmp ENDLESS_START

GENERATE_RANDOM_OBS:
	;====================================================================
	; RANDOMIZER LIN. CONGRUENTIAL FUNCTION >> X = (201 * X + 251) % 256
	;====================================================================
	ldi temp, 201
	mul seed, temp
	mov seed, R0
	ldi temp, 251
	adc seed, temp
	andi seed, 255
	mov obs_det, seed
	andi obs_det, 1
	ret
	
;====================================================================
; STATE TRACKING/CHANGING UTILITIES
;====================================================================

change_state:
	cpi state, 0
	breq state_to_1
	cpi state, 1
	breq state_to_0
	cpi state, 2
	breq MAIN

state_to_1:
	ldi state, 1
	reti

state_to_0:
	ldi state, 0
	reti

;====================================================================
; LED / LIFE COUNTER UTILITIES (LIFE STORED IN XH)
;====================================================================

INIT_LED:
	ser temp ; load $FF to temp
	out DDRC,temp ; Set PORTA to output = 0x11111111
	ldi temp, 0x07
	out PORTC, temp ; Update LEDS
	ret

UPDATE_LED:
	cpi XH, 3
	breq LIFE_3
	cpi XH, 2
	breq LIFE_2
	cpi XH, 1
	breq LIFE_1
	rjmp LIFE_0

LIFE_3:
	ldi r21, 0x07
	out PORTC, r21
	ret

LIFE_2:
	ldi r21, 0x03
	out PORTC, r21
	ret

LIFE_1:
	ldi r21, 0x01
	out PORTC, r21
	ret

LIFE_0:
	ldi r21, 0x00
	out PORTC, r21
	ret

;====================================================================
; CODE SEGMENT CONT.
;====================================================================

ENDLESS_START:
	;====================================================================
	; ENDLESS LOOP FOR GAME START : STATE = 0 
	;====================================================================
	ldi temp, 0
	cpi state, 1
	breq ENDLESS_RUN
	cpi state, 2
	breq ENDLESS_END
	subi seed, -1
	rjmp ENDLESS_START

ENDLESS_RUN:
	;====================================================================
	; ENDLESS LOOP FOR GAME RUNNING : STATE = 1
	;====================================================================
	ldi XL, 3
	ENDLESS_RUN_LOOP:
	cpi state, 0
	breq ENDLESS_START
	cpi state, 2
	breq ENDLESS_END
	rcall INIT_TIMER
	WAIT_FOR_TIMER:
		cpi temp2, 1
		breq TIMER_UP
		rjmp WAIT_FOR_TIMER
	TIMER_UP:
	subi XL, -1
	andi XL, 3
	rcall SHIFT_LEFT_BOARD
	rcall INCREMENT_SCORE
	rcall INIT_LCD_MAIN
	rjmp ENDLESS_RUN_LOOP

ENDLESS_END:
	;====================================================================
	; ENDLESS LOOP FOR GAME OVER : STATE = 2
	;====================================================================
	rcall INIT_LCD_MAIN
	ENDLESS_END_LOOP:
	cpi state, 0
	breq ENDLESS_START
	cpi state, 1
	breq ENDLESS_RUN
	rjmp ENDLESS_END_LOOP

;====================================================================
; INIT INTERRUPT
;====================================================================

INIT_INTERRUPT:
	ldi temp,0b00001010		; set int on falling edge
	out MCUCR,temp
	ldi temp,0b11100000		; set int enabled for 0 and 1
	out GICR,temp
	sei
	reti

;====================================================================
; TIMER INTERRUPT HANDLER
;====================================================================
ISR_TCOM0:
	ldi YH, high(TIMER_COUNTER_POINTER)
	ldi YL, low(TIMER_COUNTER_POINTER)
	ld temp, Y
	subi temp, 2
	st Y, temp
	ldi temp2, 1
	reti

;====================================================================
; BOARD INIT FUNCTIONS
;====================================================================

INIT_ALLOCATE_BOARD:
	;====================================================================
	; ALLOCATE 2x16 SPACE IN SRAM TO STORE BOARD VALUES
	; LOOP THROUGH IT WITH COUNTER SET ON 32
	;====================================================================
	ldi temp, 64
	ldi ZH, high(SRAM_ARRAY_POINTER)
	ldi ZL, low(SRAM_ARRAY_POINTER)
	
	LOOP_ALLOCATE_BOARD:
	tst temp
	breq END_ALLOCATE_BOARD
	rcall STORE_GAME_ELEMENT
	rjmp LOOP_ALLOCATE_BOARD
	END_ALLOCATE_BOARD:
	ret

STORE_GAME_ELEMENT:
	;====================================================================
	; DRIVER METHOD TO STORE CHARACTER AND SPACES
	;====================================================================
	cpi temp, 64
	breq STORE_CHARACTER
	rjmp STORE_SP

STORE_CHARACTER:
	;====================================================================
	; STORING CHARACTER (X)
	;====================================================================
	ldi temp2, CHAR
	st Z+, temp2 ; 
	dec temp
	ret
	
STORE_SP:
	;====================================================================
	; STORING SPACES 
	;====================================================================
	ldi temp2, BLANK
	st Z+ , temp2 ; 
	dec temp
	ret

;====================================================================
; INCREMENTING SCORE 
;====================================================================

INCREMENT_SCORE:
	ldi ZH, high(SRAM_ARRAY_POINTER)
	ldi ZL, SRAM_SCORE_POINTER
	LOOP_SCORE:
	ld score, Z
	cpi score, 0x39
	brne NORMAL_INC
	ldi score, 0x30
	st Z, score
	dec ZL
	rjmp LOOP_SCORE
	NORMAL_INC:
	subi score, -1
	st Z, score
	ret

;====================================================================
; BOARD SHIFTING FUNCTIONS
;====================================================================

SHIFT_LEFT_BOARD:
	;====================================================================
	; BOARD SHIFTING DRIVER METHOD
	;====================================================================
	ldi temp, 64
	ldi ZH, high(SRAM_ARRAY_POINTER)
	ldi ZL, low(SRAM_ARRAY_POINTER)
	
	LOOP_SHIFT_LEFT_BOARD:
	;subi YH, 2
	cpi state, 2
	breq ENDLESS_END

	tst temp
	breq END_SHIFT_LEFT_BOARD
	rjmp SHIFT_GAME_ELEMENT
	
	END_SHIFT_LEFT_BOARD:
	cpi position, 0
	breq CHAR_AT_POS_0
	rjmp CHAR_AT_POS_1

	END_CHECK_CHAR_POS:
	rcall GENERATE_RANDOM_OBS
	cpi obs_det, 0
	breq NEW_OBS_AT_POS_0
	rjmp NEW_OBS_AT_POS_1

	END_CHECK_NEW_OBS:
	reti

SHIFT_GAME_ELEMENT:
	;====================================================================
	; SHIFTING THE BOARD WHILE KEEPING TRACK OF THE CASE WHEN THE 
	; CHARACTER HITS AN OBSTACLE
	;====================================================================
	cli
	adiw Z, 1
	ld temp2, Z
	subi ZL, 1
	st Z, temp2

	; if not obs, skip
	cpi temp2, BLOCK
	brne SKIP_HIT

	; else, if pos = 0
	cpi position, 0
	brne CHECK_HIT_AT_POS_1

	;pos = 0, obs
	CHECK_HIT_AT_POS_0:
		cpi temp, 64
		brne SKIP_HIT
		; if temp = 32
		dec XH
		rcall UPDATE_LED
		rjmp SKIP_HIT

	; pos = 1, obs
	CHECK_HIT_AT_POS_1:
		cpi temp, 32
		brne SKIP_HIT
		dec XH
		rcall UPDATE_LED
		rjmp SKIP_HIT

	SKIP_HIT:
	cpi XH, 0
	breq OUT_OF_LIFE
	adiw Z, 1
	dec temp
	sei
	rjmp LOOP_SHIFT_LEFT_BOARD

;====================================================================
; END GAME HANDLER
; IF WHILE SHIFTING, LIFE HAS BEEN DEPLETED TO 0, END THE GAME
;====================================================================

OUT_OF_LIFE:
	ldi state, 2
	rcall LCD_OVER
	rjmp ENDLESS_END

CHECK_END_GAME:
	cpi XH, 0
	breq END_GAME

END_GAME:
	ldi state, 2
	ret

;====================================================================
; BOARD SHIFTING UTILITIES TO SHIFT CHARACTERS AND NEW OBSTACLES
;====================================================================

CHAR_AT_POS_0:
	cli
	ldi YH, high(SRAM_ARRAY_POINTER)
	ldi YL, low(SRAM_ARRAY_POINTER)
	ldi temp2, CHAR
	st Y, temp2
	sei
	rjmp END_CHECK_CHAR_POS

CHAR_AT_POS_1:
	cli
	ldi YH, high(SRAM_ARRAY_POINTER)
	ldi YL, low(SRAM_ARRAY_POINTER)
	adiw Y, 32
	ldi temp2, CHAR
	st Y, temp2
	sei
	rjmp END_CHECK_CHAR_POS

NEW_OBS_AT_POS_0:
	ldi YH, high(SRAM_ARRAY_POINTER)
	ldi YL, low(SRAM_ARRAY_POINTER)
	adiw Y, 31
	ldi temp2, BLANK
	st Y, temp2
	cpi XL, 0
	brne SKIP_OBS_AT_POS_0
	ldi temp2, BLOCK
	st Y, temp2
	SKIP_OBS_AT_POS_0:
	adiw Y, 32
	ldi temp2, BLANK
	st Y, temp2
	rjmp END_CHECK_NEW_OBS
	
NEW_OBS_AT_POS_1:
	ldi YH, high(SRAM_ARRAY_POINTER)
	ldi YL, low(SRAM_ARRAY_POINTER)
	adiw Y, 31
	ldi temp2, BLANK
	st Y, temp2
	adiw Y, 32
	ldi temp2, BLANK
	st Y, temp2
	cpi XL, 0
	brne SKIP_OBS_AT_POS_1
	ldi temp2, BLOCK
	st Y, temp2
	SKIP_OBS_AT_POS_1:
	rjmp END_CHECK_NEW_OBS

;====================================================================
; INTERRUPT HANDLERS
;====================================================================

UP_BUTTON:
	;====================================================================
	; IF POSITION = 1, CHANGE IT TO 0 AND
	; CHANGE THE CHARACTER POSITION IN THE SRAM ARRAY AS WELL
	;====================================================================
	cpi state, 0
	breq END_INT_1_PRC
	cpi position, 0
	breq END_INT_1_PRC
	ldi position, 0
	ldi YH, high(SRAM_ARRAY_POINTER)
	ldi YL, low(SRAM_ARRAY_POINTER)
	ldi temp, CHAR
	st Y, temp
	adiw YL, 32
	ldi temp, BLANK
	st Y, temp
	rcall INIT_LCD_MAIN
	END_INT_1_PRC:
	reti

DOWN_BUTTON:
	;====================================================================
	; IF POSITION = 0, CHANGE IT TO 1
	; CHANGE THE CHARACTER POSITION IN THE SRAM ARRAY AS WELL
	;====================================================================
	cpi state, 0
	breq END_INT_2_PRC
	cpi position, 1
	breq END_INT_2_PRC
	ldi position, 1
	ldi YH, high(SRAM_ARRAY_POINTER)
	ldi YL, low(SRAM_ARRAY_POINTER)
	ldi temp, BLANK
	st Y, temp
	adiw YL, 32
	ldi temp, CHAR
	st Y, temp
	rcall INIT_LCD_MAIN
	END_INT_2_PRC:
	reti

START_BUTTON:
	;====================================================================
	; TOGGLING STATE
	;====================================================================
	cpi state, 1
	breq DISABLE_START_BUTTON
	rcall change_state
	DISABLE_START_BUTTON:
	reti

;====================================================================
; LOADING STRING TO Z TO BE DISPLAYED
;====================================================================

LCD_START:
	ldi ZH,high(2*message_start) ; Load high part of byte address into ZH
	ldi ZL,low(2*message_start) ; Load low part of byte address into ZL
	ret

LCD_SCORE_TEXT:
	ldi ZH,high(2*message_score) ; Load high part of byte address into ZH
	ldi ZL,low(2*message_score) ; Load low part of byte address into ZL
	ret
	
LCD_SCORE:
	ldi ZH, high(SRAM_SCORE_POINTER)
	ldi ZL, low(SRAM_SCORE_POINTER)
	subi ZL, 6
	ret

LCD_OVER:
	ldi ZH,high(2*message_game_over) ; Load high part of byte address into ZH
	ldi ZL,low(2*message_game_over) ; Load low part of byte address into ZL
	ret

;====================================================================
; SETUP LCD
;====================================================================

INIT_LCD_MAIN:
	ser temp
	out DDRA,temp ; Set port A as output
	out DDRB,temp ; Set port B as output 

	cpi state,0
	breq STATE_0

	cpi state, 1
	breq STATE_1

	cpi state, 2
	breq STATE_2

	;====================================================================
	; CASE IF GAME STARTING
	;====================================================================
	STATE_0:
		rcall INIT_LCD_LINE_1
		rcall LCD_START
		rcall LOADBYTE

		rcall INIT_LCD_LINE_2
		rcall LCD_SCORE_TEXT
		rcall LOADBYTE

		rcall LCD_SCORE
		rcall INIT_LCD_LINE_2_SCORE
		ldi temp, 7
		rcall LOADBYTE_WITH_LIMIT

		rjmp END_LCD
		
	;====================================================================
	; CASE IF GAME RUNNING
	;====================================================================
	STATE_1:
		ldi ZH, high(SRAM_ARRAY_POINTER)
		ldi ZL, low(SRAM_ARRAY_POINTER)	
		rcall INIT_LCD_LINE_1
		ldi temp, 32
		rcall LOADBYTE_WITH_LIMIT
	
		ldi ZH, high(SRAM_ARRAY_POINTER)
		ldi ZL, low(SRAM_ARRAY_POINTER)
		adiw Z, 32
		rcall INIT_LCD_LINE_2
		ldi temp, 32
		rcall LOADBYTE_WITH_LIMIT
		rjmp END_LCD

	;====================================================================
	; CASE IF GAME IS OVER
	;====================================================================
	STATE_2:
		rcall INIT_LCD_LINE_1
		rcall LCD_OVER
		rcall LOADBYTE

		rcall INIT_LCD_LINE_2
		rcall LCD_SCORE_TEXT
		rcall LOADBYTE

		rcall LCD_SCORE
		rcall INIT_LCD_LINE_2_SCORE
		ldi temp, 7
		rcall LOADBYTE_WITH_LIMIT

		rjmp END_LCD
	
	END_LCD:
		ret

;====================================================================
; LCD WRITING UTILITIES
;====================================================================

LOADBYTE:
	;====================================================================
	; LOADBYTE UNTIL ZERO FOUND
	;====================================================================
	lpm ; Load byte from program memory into r0
	tst r0 ; Check if we've reached the end of the message
	breq END_LOAD ; If so, quit
	mov A, r0 ; Put the character onto Port B
	rcall WRITE_TEXT
	adiw ZL,1 ; Increase Z registers
	rjmp LOADBYTE
	END_LOAD:
		reti


LOADBYTE_WITH_LIMIT:
	;====================================================================
	; LOADBYTE WITH LIMITED BYTE UP TO [temp] BYTES (FOR BOARD & SCORE)
	;====================================================================
	tst temp
	breq END_LOAD_WITH_LIMIT ; If so, quit
	dec temp
	ld temp2, Z+
	mov A, temp2 ; Put the character onto Port B
	rcall WRITE_TEXT
	rjmp LOADBYTE_WITH_LIMIT
	END_LOAD_WITH_LIMIT:
		reti
	
INIT_LCD_LINE_1:
	;====================================================================
	; CHANGING CURSOR TO THE FIRST SPACE ON THE FIRST LINE
	;====================================================================
	cbi PORTA,1 ; CLR RS
	ldi PB,0x38 ; MOV DATA,0x38 --> 8bit, 2line, 5x7
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	cbi PORTA,1 ; CLR RS
	ldi PB,$0C ; MOV DATA,0x0E --> disp ON, cursor OFF, blink OFF
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	rcall CLEAR_LCD ; CLEAR LCD
	cbi PORTA,1 ; CLR RS
	ldi PB,$06 ; MOV DATA,0x06 --> increase cursor, display sroll OFF
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	ret

INIT_LCD_LINE_2:
	;====================================================================
	; CHANGING CURSOR TO THE FIRST SPACE ON THE SECOND LINE
	;====================================================================
	cbi PORTA,1 ; CLR RS
	ldi PB,0x38 ; MOV DATA,0x38 --> 8bit, 2line, 5x7
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	cbi PORTA,1 ; CLR RS
	ldi PB,$0C ; MOV DATA,0x0E --> disp ON, cursor OFF, blink OFF
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	cbi PORTA,1 ; CLR RS
	ldi PB,$06 ; MOV DATA,0x06 --> increase cursor, display sroll OFF
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	cbi PORTA,1 ; CLR RS
	ldi PB,$40 ; MOV DATA,0x06 --> increase cursor to line 2, display sroll OFF
	ori PB,0x80
	out PORTB, PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	ret

INIT_LCD_LINE_2_SCORE:
	;====================================================================
	; CHANGING CURSOR TO THE FIRST SPACE ON THE SECOND LINE SCORE POS
	;====================================================================
	cbi PORTA,1 ; CLR RS
	ldi PB,0x38 ; MOV DATA,0x38 --> 8bit, 2line, 5x7
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	cbi PORTA,1 ; CLR RS
	ldi PB,$0C ; MOV DATA,0x0E --> disp ON, cursor OFF, blink OFF
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	cbi PORTA,1 ; CLR RS
	ldi PB,$06 ; MOV DATA,0x06 --> increase cursor, display sroll OFF
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	cbi PORTA,1 ; CLR RS
	ldi PB,$48 ; MOV DATA,0x49 --> increase cursor to line 2 pos 8, display sroll OFF
	ori PB,0x80
	out PORTB, PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	ret

CLEAR_LCD:
	;====================================================================
	; CLEAR ENTIRE LINE IN AN LCD
	;====================================================================
	cbi PORTA,1 ; CLR RS
	ldi PB,$01 ; MOV DATA,0x01
	out PORTB,PB
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	ret

WRITE_TEXT:
	;====================================================================
	; WRITING A BYTE TO APPOINTED CURSOR ADDRESS ON LCD
	;====================================================================
	sbi PORTA,1 ; SETB RS
	out PORTB, A
	sbi PORTA,0 ; SETB EN
	cbi PORTA,0 ; CLR EN
	ret

;====================================================================
; DATA
;====================================================================

message_start:
.db "BLOCK RACER, START!", 0

message_score:
.db "SCORE : ", 0

message_game_over:
.db "GAME OVER", 0

