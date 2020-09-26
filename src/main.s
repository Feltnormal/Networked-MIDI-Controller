.syntax unified
.global main, EXTI0_IRQHandler, EXTI1_IRQHandler

.include "macros.s"

@ WIRING INFORMATION
@	Control line: PE12 (sender) to PH0 (receiver)
@	Clock line: PE13 (sender) to PH1 (receiver)
@	Data lines:
		@	Frequency: PE14 (sender) to PE11 (receiver)
		@	Amplitude: PE15 (sender) to PE10 (receiver)

main:
	bl init_gpio
	bl init_audio

	@clear and delare pins
	GPIOx_ODR_clear	H, 0
	GPIOx_ODR_clear E, 12
	GPIOx_ODR_clear H, 1
	GPIOx_ODR_clear E, 13
	GPIOx_ODR_clear H, 14
	GPIOx_ODR_clear E, 11

	declare_output_pin E, 15 @ second data line
	declare_input_pin_it E, 10

	NVIC_IPR_set_priority 6 1	@ EXTI0 = lower priority
	NVIC_IPR_set_priority 7 0	@ EXTI1 = high priority

set_reset:
	mov r4, #0		@frequency receiver
	mov r9, #4		@our offset for notes
	mov r11, #0 	@timing index
	ldr r10, =timing
	ldr r5, =#20000
	ldr r6, [r10, r11]
	ldr r7, =notes
	b load_next_note

loop:
	bl play_square
	cmp r5, #0
	beq mute
	subs r5,#1
	b loop

mute:
	ldr r5, =#48000			@ reset note timer
	mov r0, #0
	mov r1, #0
	ldr r6, [r10, r11] 			@reset rest timer
	bl change_square
	rest:
		bl play_square
		cmp r6, #0
		beq load_next_note
		subs r6, #1
		b rest

process_msg:
	cmp r8, #0		//if no message has been loaded then only play the first note
	beq error_loop

	add r9, #4			@load next frequency in memory
	add r11, #4			@load next note duration

	@proccess frequency
	lsr r4, #16

	@process amplitude (shifted by 17 to account for bug)
	lsr r8, #17

	@input the new frequency and amplitude
	mov r0, r4
	mov r1, r8
	bl change_square
	b loop

@ r0: frequency
@ r1: amplitude
load_next_note:
	cmp r9, #40
	beq set_reset
	ldr r0, [r7, r9] @each note is one word apart
	ldr r1, [r7]

send_msg:
	mov r3, #32               @ counter
	mov r2, r0                @ store frequency to send
	mov r5, r1				@ store amplitude to send
	mov r6, #0				@ change to 1 when reading amplitude
	mov r4, #0				@ reset frequency receiver
	mov r8, #0                @ reset amplitude receiver

	GPIOx_ODR_set E, 12       @ turn on control

 	@checks if clock line is plugged in
  	GPIOx_IDR_read H, 0
  	cmp r0, #0
  	beq error_loop

  	GPIOx_ODR_clear E, 12		@ turn on control
  	b process_msg

start_send_freq:
  	ands r0, r2, #1
  	bgt send_high_F
  	beq send_low_F

start_send_amp:
  	ands r1, r5, #1
  	bgt send_high_A
  	beq send_low_A

finish_send_freq:
  	GPIOx_ODR_toggle E, 13    @ toggle clock
 	ror r2, #1
  	subs r3, #1
  	cmp r3, #16
  	beq start_send_amp
  	b start_send_freq

finish_send_amp:
	mov r6, #1				@signals that amplitude is being sent
  	GPIOx_ODR_toggle E, 13    @ toggle clock
 	ror r5, #1
  	subs r3, #1
  	beq end_message
  	b start_send_amp

send_high_F: 				@send high bit
  	GPIOx_ODR_set E, 14
  	b finish_send_freq
send_low_F:					@send low bit
  	GPIOx_ODR_clear E, 14
  	b finish_send_freq

send_high_A: 				@send high bit
  	GPIOx_ODR_set E, 15
  	b finish_send_amp
send_low_A:					@send low bit
  	GPIOx_ODR_clear E, 15
  	b finish_send_amp

end_message: 				@END OF MESSAGE COMMAND
  	bx lr
@@@@@@@@@@@@@@@ Interrupts + auxillary functions here  @@@@@@@@@@@@@@@@@@

.type EXTI0_IRQHandler, %function
EXTI0_IRQHandler:
	EXTI_PR_clear_pending 0
	push {lr}
	bl start_send_freq
	pop {lr}
	bx lr

.type EXTI1_IRQHandler, %function @this function is called inside of EXTI0 Handler
EXTI1_IRQHandler: 		@reads a bitstring from LSB to MSB
	EXTI_PR_clear_pending 1
	push {lr}
	@ read amplitude
	bl read_amp
	@ read frequency
	GPIOx_IDR_read E, 11
	lsl r4, #1
	orr r4, r4, r0
	pop {lr}
	bx lr

read_amp:
	cmp r6, #1	@checks to see if amplitude message has started sending
	beq start_read_amp
	bx lr
	start_read_amp:
		GPIOx_IDR_read E, 10
		lsl r8, #1
		orr r8, r8, r0
		bx lr

error_loop:
	mov r0, #440
	ldr r1, =#0x7FFF
	bl change_square
	error:
		bl play_square
		b error
@@@@@@@@@@@@@@@@@@@@@@  DATA STARTS HERE  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.data
	notes:
		.word 0b1111111111111110 @amplitude
		.word 0b0010010100000000 @E
		.word 0b0010010100000000 @E
		.word 0b0010010100000000 @E
		.word 0b1011001000000000 @D#
		.word 0b1110110000000000 @A
		.word 0b1100110000000000 @G#
		.word 0b1100110000000000 @G#
		.word 0b1100110000000000 @G#
		.word 0b1010001000000000 @C#

	timing:	@8000 [short note], 96000 [long note]
		.word 8000
		.word 8000
		.word 8000
		.word 8000
		.word 96000
		.word 96000
		.word 8000
		.word 8000
		.word 8000
		.word 8000




