; debug_mixed.S — asm functions with debug info for mixed C+asm test
	section	text,code
	xdef	_add_values
	xdef	_mul_values

_add_values:
	move.l	4(sp),d0
	add.l	8(sp),d0
	rts

_mul_values:
	move.l	4(sp),d0
	move.l	8(sp),d1
	muls.w	d1,d0
	rts
