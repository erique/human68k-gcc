; hello.S — basic DOS PRINT test
	include	"dos.inc"
	section	text,code

	PRINT	message
	EXIT

message:
	dc.b	'Hello from vasm',$0d,$0a,0
