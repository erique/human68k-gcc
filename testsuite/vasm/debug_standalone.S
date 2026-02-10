; debug_standalone.S — test DWARF debug info from vasm
	include	"dos.inc"
	section	text,code

_start:
	pea	msg
	dc.w	_DOS_PRINT
	addq.l	#4,sp
	clr.w	-(sp)
	dc.w	_DOS_EXIT2

msg:
	dc.b	'debug ok',$0d,$0a,0
