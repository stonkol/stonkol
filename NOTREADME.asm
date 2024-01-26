;
; ************ Console and Printer Output ************
;
OUTP:
	PUSH	AX
OUTLP:
	IN	STAT
	AND	AL,TBMT
	JZ	OUTLP
	POP	AX
	OUT	DATA
	RET	L

PRINT:
	PUSH	SI
	SEG	CS
	MOV	SI,[PREAR]
	CALL	INCPQ
PRINLP:
	SEG	CS
	CMP	SI,[PFRONT]
	JNZ	PRNCHR
;Print queue is full
	PUSH	AX
	CALL	STATUS,BIOSSEG	;Poll and maybe print something
	POP	AX
	JMPS	PRINLP
PRNCHR:
	SEG	CS
	MOV	[PREAR],SI
	SEG	CS
	MOV	[SI],AL
	POP	SI
	RET	L
;
; ************ Auxiliary I/O ************
;
AUXIN:
	IN	AUXSTAT
	AND	AL,DAV
	JZ	AUXIN
	IN	AUXDATA
	RET	L

AUXOUT:
	PUSH	AX
AUXLP:
	IN	AUXSTAT
	AND	AL,TBMT
	JZ	AUXLP
	POP	AX
	OUT	AUXDATA
	RET	L
;
; ************ 1771/1793-type controller disk I/O ************
;
TARBELL:EQU	TARBELLSD+TARBELLDD
CROMEMCO:EQU	CROMEMCO4FDC+CROMEMCO16FDC

WD1791:	EQU	SCP+TARBELLDD+CROMEMCO16FDC
WD1771:	EQU	TARBELLSD+CROMEMCO4FDC

	IF	WD1791
READCOM:EQU	80H
WRITECOM:EQU	0A0H
	ENDIF

	IF	WD1771
READCOM:EQU	88H
WRITECOM:EQU	0A8H
	ENDIF

	IF	SCP
SMALLBIT:EQU	10H
BACKBIT:EQU	04H
DDENBIT:EQU	08H
DONEBIT:EQU	01H
DISK:	EQU	0E0H
	ENDIF

	IF	TARBELL
BACKBIT:EQU	40H
DDENBIT:EQU	08H
DONEBIT:EQU	80H
DISK:	EQU	78H
	ENDIF

	IF	CROMEMCO
SMALLBIT:EQU	10H
BACKBIT:EQU	0FDH		; Send this to port 4 to select back.
DDENBIT:EQU	40H
DONEBIT:EQU	01H
DISK:	EQU	30H
	ENDIF

	IF	SMALLDS-1
SMALLDDSECT:	EQU	8
	ENDIF

	IF	SMALLDS
SMALLDDSECT:	EQU	16
	ENDIF

	IF	LARGEDS-1
LARGEDDSECT:	EQU	8
	ENDIF

	IF	LARGEDS
LARGEDDSECT:	EQU	16
	ENDIF
;
;
; Disk read function.
;
; On entry:
;	AL = Disk I/O driver number
;	BX = Disk transfer address in DS
;	CX = Number of sectors to transfer
;	DX = Logical record number of transfer
; On exit:
;	CF clear if transfer complete
;
;	CF set if hard disk error.
;	CX = number of sectors left to transfer.
;	AL = disk error code
;		0 = write protect error
;		2 = not ready error
;		4 = "data" (CRC) error
;		6 = seek error
;		8 = sector not found
;	       10 = write fault
;	       12 = "disk" (none of the above) error
;
READ:
	CALL	SEEK		;Position head
	JC	ERROR
	PUSH	ES		; Make ES same as DS.
	MOV	BX,DS
	MOV	ES,BX
RDLP:
	CALL	READSECT	;Perform sector read
	JC	POPESERROR
	INC	DH		;Next sector number
	LOOP	RDLP		;Read each sector requested
	CLC			; No errors.
	POP	ES		; Restore ES register.
	RET	L
;
; Disk write function.
; Registers same on entry and exit as read above.
;
WRITE:
	CALL	SEEK		;Position head
	JC	ERROR
WRTLP:
	CALL	WRITESECT	;Perform sector write
	JC	ERROR
	INC	DH		;Bump sector counter
	LOOP	WRTLP		;Write CX sectors
	CLC			; No errors.
WRITERET:
	RET	L

POPESERROR:
	POP	ES		; Restore ES register.
ERROR:
	MOV	BL,-1
	SEG	CS
	MOV	[DI],BL		; Indicate we don't know where head is.
	MOV	SI,ERRTAB
GETCOD:
	INC	BL		; Increment to next error code.
	SEG	CS
	LODB
	TEST	AH,AL		; See if error code matches disk status.
	JZ	GETCOD		; Try another if not.
	MOV	AL,BL		; Now we've got the code.
	SHL	AL		; Multiply by two.
	STC
	RET	L

ERRTAB:
	DB	40H		;Write protect error
	DB	80H		;Not ready error
	DB	8		;CRC error
	DB	2		;Seek error
	DB	10H		;Sector not found
	DB	20H		;Write fault
	DB	7		;"Disk" error
;
;
; RESTORE for PerSci drives.
; Doesn't exist yet for Tarbell controllers.
;
	IF	FASTSEEK*TARBELL
HOME:
RESTORE:
	RET
	ENDIF

	IF	FASTSEEK*CROMEMCO4FDC
RESTORE:
	MOV	AL,0C4H		;READ ADDRESS command to keep head loaded
	OUT	DISK
	MOV	AL,77H
	OUT	4
CHKRES:
	IN	4
	AND	AL,40H
	JZ	RESDONE
	IN	DISK+4
	TEST	AL,DONEBIT
	JZ	CHKRES
	IN	DISK
	JP	RESTORE		;Reload head
RESDONE:
	MOV	AL,7FH
	OUT	4
	CALL	GETSTAT
	MOV	AL,0
	OUT	DISK+1		;Tell 1771 we're now on track 0
	RET
	ENDIF

	IF	FASTSEEK*CROMEMCO16FDC
RESTORE:
	MOV	AL,0D7H		; Turn on Drive-Select and Restore.
	OUTB	4
	PUSH	AX
	AAM			; 10 uS delay.
	POP	AX
RESWAIT:
	INB	4		; Wait till Seek Complete is active.
	TEST	AL,40H
	JNZ	RESWAIT
	MOV	AL,0FFH		; Turn off Drive-Select and Restore.
	OUTB	4
	SUB	AL,AL		; Tell 1793 we're on track 0.
	OUTB	DISK+1
	RET
	ENDIF
;
; Subroutine to move the read/write head to the desired track.
; Usually falls through to DCOM unless special handling for
; PerSci drives is required in which case go to FASTSK.
;
	IF	SCP+CROMEMCO+TARBELL*(FASTSEEK-1)
MOVHEAD:
	ENDIF

	IF	CROMEMCO*FASTSEEK
	TEST	AH,SMALLBIT	; Check for PerSci.
	JNZ	FASTSK
	ENDIF

DCOM:
	OUT	DISK
	PUSH	AX
	AAM			;Delay 10 microseconds
	POP	AX
GETSTAT:
	IN	DISK+4
	TEST	AL,DONEBIT

	IF	TARBELL
	JNZ	GETSTAT
	ENDIF

	IF	SCP+CROMEMCO
	JZ	GETSTAT
	ENDIF

	IN	DISK
	RET
;
; Fast seek code for PerSci drives.
; Tarbell not installed yet.
;
	IF	FASTSEEK*TARBELL
MOVHEAD:
FASTSK:
	RET
	ENDIF

	IF	FASTSEEK*CROMEMCO
FASTSK:
	MOV	AL,6FH
	OUT	4
	MOV	AL,18H
	CALL	DCOM
SKWAIT:
	IN	4
	TEST	AL,40H
	JNZ	SKWAIT
	MOV	AL,7FH
	OUT	4
	MOV	AL,0
	RET
	ENDIF

CURDRV:	DB	-1
;
