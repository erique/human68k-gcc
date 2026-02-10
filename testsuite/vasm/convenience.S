; convenience.S — test convenience macros
	include	"dos.inc"
	include	"iocs.inc"
	section	text,code

	; Test DOS convenience macro
	PRINT	msg_dos

	; Test IOCS convenience macro (B_PRINT uses BIOS)
	B_PRINT	msg_iocs

	EXIT

msg_dos:
	dc.b	'DOS PRINT ok',$0d,$0a,0
msg_iocs:
	dc.b	'IOCS B_PRINT ok',$0d,$0a,0
