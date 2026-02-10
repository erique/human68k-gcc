; mixed_c_asm.S — assembly function callable from C
	section	text,code
	xdef	add_asm

add_asm:
	move.l	4(sp),d0
	add.l	8(sp),d0
	rts
