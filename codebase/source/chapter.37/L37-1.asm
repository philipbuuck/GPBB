; Fast run length slice line drawing implementation for mode 0x13, the VGA's
; 320x200 256-color mode.
; Draws a line between the specified endpoints in color Color.
; C near-callable as:
;  void LineDraw(int XStart, int YStart, int XEnd, int YEnd, int Color)
; Tested with TASM 4.0 and linked with L15-2.C:
;   bcc -ms l15-2.c l16-1.asm
; Checked by Jim Mischel 11/30/94

SCREEN_WIDTH    	equ 320
SCREEN_SEGMENT  		equ 0a000h
    .model  small
    .code

; Parameters to call.
parms   struc
    	dw  ?   				;pushed BP
    	dw  ?   				;pushed return address
XStart  dw  ?				;X start coordinate of line
YStart  dw  ?				;Y start coordinate of line
XEnd    dw  ?				;X end coordinate of line
YEnd    dw  ?				;Y end coordinate of line
Color   db  ?				;color in which to draw line
        db  ?				;dummy byte because Color is really a word
parms   ends

; Local variables.
AdjUp   		equ -2  			;error term adjust up on each advance
AdjDown 		equ -4  			;error term adjust down when error term turns over
WholeStep 	equ -6      		;minimum run length
XAdvance 	equ -8      		;1 or -1, for direction in which X advances
LOCAL_SIZE 	equ  8
    public  _LineDraw
_LineDraw   proc    near
    cld
    push    bp  				;preserve caller's stack frame
    mov bp,sp   				;point to our stack frame
    sub sp,LOCAL_SIZE   			;allocate space for local variables
    push    si  				;preserve C register variables
    push    di
    push    ds  				;preserve caller's DS
; We'll draw top to bottom, to reduce the number of cases we have to handle,
; and to make lines between the same endpoints always draw the same pixels.
    mov ax,[bp].YStart
    cmp ax,[bp].YEnd
    jle LineIsTopToBottom
    xchg    [bp].YEnd,ax			;swap endpoints
    mov [bp].YStart,ax  
    mov bx,[bp].XStart
    xchg    [bp].XEnd,bx
    mov [bp].XStart,bx  
LineIsTopToBottom:
; Point DI to the first pixel to draw.
    mov dx,SCREEN_WIDTH
    mul dx              			;YStart * SCREEN_WIDTH
    mov si,[bp].XStart
    mov di,si
    add di,ax           			;DI = YStart * SCREEN_WIDTH + XStart
                				; = offset of initial pixel
; Figure out how far we're going vertically (guaranteed to be positive).
    mov cx,[bp].YEnd
    sub cx,[bp].YStart  			;CX = YDelta
; Figure out whether we're going left or right, and how far we're going
; horizontally. In the process, special-case vertical lines, for speed and
; to avoid nasty boundary conditions and division by 0.
    mov dx,[bp].XEnd
    sub dx,si       			;XDelta
    jnz NotVerticalLine 			;XDelta == 0 means vertical line
                				;it is a vertical line
                				;yes, special case vertical line
    mov ax,SCREEN_SEGMENT
    mov ds,ax           			;point DS:DI to the first byte to draw
    mov al,[bp].Color
VLoop:
    mov [di],al
    add di,SCREEN_WIDTH
    dec cx
    jns VLoop
    jmp Done
; Special-case code for horizontal lines.
    align   2
IsHorizontalLine:
    mov ax,SCREEN_SEGMENT
    mov es,ax           			;point ES:DI to the first byte to draw
    mov al,[bp].Color
    mov ah,al       			;duplicate in high byte for word access
    and bx,bx   				;left to right?
    jns DirSet  				;yes
    sub di,dx   				;currently right to left, point to left end so we
            				; can go left to right (avoids unpleasantness with
            				; right to left REP STOSW)
DirSet:
        mov     cx,dx
        inc     cx      			;# of pixels to draw
    shr cx,1    				;# of words to draw
    rep stosw   				;do as many words as possible
    adc cx,cx
    rep stosb   				;do the odd byte, if there is one
    jmp Done
; Special-case code for diagonal lines.
    align   2
IsDiagonalLine:
    mov ax,SCREEN_SEGMENT
    mov ds,ax           			;point DS:DI to the first byte to draw
    mov al,[bp].Color
    add bx,SCREEN_WIDTH 			;advance distance from one pixel to next
DLoop:
    mov [di],al
    add di,bx
    dec cx
    jns DLoop
    jmp Done

    align   2
NotVerticalLine:
    mov bx,1        			;assume left to right, so XAdvance = 1
                				;***leaves flags unchanged***
    jns LeftToRight 			;left to right, all set
    neg bx      				;right to left, so XAdvance = -1
    neg dx      				;|XDelta|
LeftToRight:
; Special-case horizontal lines.
    and cx,cx   				;YDelta == 0?
    jz  IsHorizontalLine ;yes
; Special-case diagonal lines.
    cmp cx,dx   ;YDelta == XDelta?
    jz  IsDiagonalLine 	;yes
; Determine whether the line is X or Y major, and handle accordingly.
        cmp     dx,cx
        jae     XMajor
        jmp     YMajor
; X-major (more horizontal than vertical) line.
        align   2
XMajor:
    mov ax,SCREEN_SEGMENT
    mov es,ax           			;point ES:DI to the first byte to draw
        and     bx,bx    		;left to right?
        jns     DFSet    		;yes, CLD is already set
        std              		;right to left, so draw backwards
DFSet:
        mov     ax,dx    		;XDelta
        sub     dx,dx    		;prepare for division
        div     cx              		;AX = XDelta/YDelta
                                		; (minimum # of pixels in a run in this line)
                                		;DX = XDelta % YDelta
        mov     bx,dx           		;error term adjust each time Y steps by 1;
        add     bx,bx           		; used to tell when one extra pixel should be
        mov     [bp].AdjUp,bx   		; drawn as part of a run, to account for
                                		; fractional steps along the X axis per
                                		; 1-pixel steps along Y
        mov     si,cx           		;error term adjust when the error term turns
        add     si,si           		; over, used to factor out the X step made at
        mov     [bp].AdjDown,si 		; that time
; Initial error term; reflects an initial step of 0.5 along the Y axis.
        sub     dx,si           		;(XDelta % YDelta) - (YDelta * 2)
                                		;DX = initial error term
; The initial and last runs are partial, because Y advances only 0.5 for
; these runs, rather than 1. Divide one full run, plus the initial pixel,
; between the initial and last runs.
        mov     si,cx           		;SI = YDelta
        mov     cx,ax           		;whole step (minimum run length)
        shr     cx,1
        inc     cx              		;initial pixel count = (whole step / 2) + 1;
                                		; (may be adjusted later). This is also the
                				; final run pixel count
        push    cx              		;remember final run pixel count for later
; If the basic run length is even and there's no fractional advance, we have
; one pixel that could go to either the initial or last partial run, which
; we'll arbitrarily allocate to the last run.
; If there is an odd number of pixels per run, we have one pixel that can't
; be allocated to either the initial or last partial run, so we'll add 0.5 to
; the error term so this pixel will be handled by the normal full-run loop.
        add     dx,si           		;assume odd length, add YDelta to error term
                				; (add 0.5 of a pixel to the error term)
        test    al,1            		;is run length even?
        jnz     XMajorAdjustDone 		;no, already did work for odd case, all set
        sub     dx,si           		;length is even, undo odd stuff we just did
        and     bx,bx           		;is the adjust up equal to 0?
        jnz     XMajorAdjustDone 		;no (don't need to check for odd length,
                 			; because of the above test)
        dec     cx              		;both conditions met; make initial run 1
                                		; shorter
XMajorAdjustDone:
        mov     [bp].WholeStep,ax 	;whole step (minimum run length)
        mov     al,[bp].Color   		;AL = drawing color
; Draw the first, partial run of pixels.
        rep     stosb           		;draw the final run
        add     di,SCREEN_WIDTH 		;advance along the minor axis (Y)
; Draw all full runs.
        cmp     si,1            		;are there more than 2 scans, so there are
                				; some full runs? (SI = # scans - 1)
        jna     XMajorDrawLast  		;no, no full runs
        dec     dx              		;adjust error term by -1 so we can use
                                		; carry test
        shr     si,1            		;convert from scan to scan-pair count
        jnc     XMajorFullRunsOddEntry  	;if there is an odd number of scans,
                                        	; do the odd scan now
XMajorFullRunsLoop:
        mov     cx,[bp].WholeStep 	;run is at least this long
        add     dx,bx           		;advance the error term and add an extra
        jnc     XMajorNoExtra   		; pixel if the error term so indicates
        inc     cx              		;one extra pixel in run
        sub     dx,[bp].AdjDown 		;reset the error term
XMajorNoExtra:
    rep     stosb           		;draw this scan line's run
        add     di,SCREEN_WIDTH 		;advance along the minor axis (Y)
XMajorFullRunsOddEntry:         		;enter loop here if there is an odd number
                                		; of full runs
        mov     cx,[bp].WholeStep 	;run is at least this long
        add     dx,bx           		;advance the error term and add an extra
        jnc     XMajorNoExtra2  		; pixel if the error term so indicates
        inc     cx              		;one extra pixel in run
        sub     dx,[bp].AdjDown 		;reset the error term
XMajorNoExtra2:
    rep     stosb           		;draw this scan line's run
        add     di,SCREEN_WIDTH 		;advance along the minor axis (Y)

        dec     si
        jnz     XMajorFullRunsLoop
; Draw the final run of pixels.
XMajorDrawLast:
        pop     cx              		;get back the final run pixel length
        rep     stosb           		;draw the final run

        cld                     		;restore normal direction flag
        jmp     Done
; Y-major (more vertical than horizontal) line.
        align   2
YMajor:
        mov     [bp].XAdvance,bx 		;remember which way X advances
    mov ax,SCREEN_SEGMENT
    mov ds,ax           			;point DS:DI to the first byte to draw
        mov     ax,cx           		;YDelta
        mov     cx,dx           		;XDelta
        sub     dx,dx           		;prepare for division
        div     cx              		;AX = YDelta/XDelta
                                		; (minimum # of pixels in a run in this line)
                                		;DX = YDelta % XDelta
        mov     bx,dx           		;error term adjust each time X steps by 1;
        add     bx,bx           		; used to tell when one extra pixel should be
        mov     [bp].AdjUp,bx   		; drawn as part of a run, to account for
                                		; fractional steps along the Y axis per
                                		; 1-pixel steps along X
        mov     si,cx           		;error term adjust when the error term turns
        add     si,si           		; over, used to factor out the Y step made at
        mov     [bp].AdjDown,si 		; that time

; Initial error term; reflects an initial step of 0.5 along the X axis.
        sub     dx,si           		;(YDelta % XDelta) - (XDelta * 2)
                                		;DX = initial error term
; The initial and last runs are partial, because X advances only 0.5 for
; these runs, rather than 1. Divide one full run, plus the initial pixel,
; between the initial and last runs.
        mov     si,cx           		;SI = XDelta
        mov     cx,ax           		;whole step (minimum run length)
        shr     cx,1
        inc     cx              		;initial pixel count = (whole step / 2) + 1;
                                		; (may be adjusted later)
        push    cx              		;remember final run pixel count for later

; If the basic run length is even and there's no fractional advance, we have
; one pixel that could go to either the initial or last partial run, which
; we'll arbitrarily allocate to the last run.
; If there is an odd number of pixels per run, we have one pixel that can't
; be allocated to either the initial or last partial run, so we'll add 0.5 to
; the error term so this pixel will be handled by the normal full-run loop.
        add     dx,si           		;assume odd length, add XDelta to error term
        test    al,1            		;is run length even?
        jnz     YMajorAdjustDone 		;no, already did work for odd case, all set
        sub     dx,si           		;length is even, undo odd stuff we just did
        and     bx,bx           		;is the adjust up equal to 0?
        jnz     YMajorAdjustDone 		;no (don't need to check for odd length,
                 ; because of the above test)
        dec     cx              		;both conditions met; make initial run 1
                                		; shorter
YMajorAdjustDone:
        mov     [bp].WholeStep,ax 	;whole step (minimum run length)
        mov     al,[bp].Color     	;AL = drawing color
        mov     bx,[bp].XAdvance  	;which way X advances
; Draw the first, partial run of pixels.
YMajorFirstLoop:
        mov     [di],al         		;draw the pixel
        add     di,SCREEN_WIDTH 		;advance along the major axis (Y)
        dec     cx
        jnz     YMajorFirstLoop
        add     di,bx           		;advance along the minor axis (X)
; Draw all full runs.
        cmp     si,1            		;# of full runs. Are there more than 2
                				; columns, so there are some full runs?
                				; (SI = # columns - 1)
        jna     YMajorDrawLast  		;no, no full runs
        dec     dx              		;adjust error term by -1 so we can use
                                		; carry test
        shr     si,1            		;convert from column to column-pair count
        jnc     YMajorFullRunsOddEntry  	;if there is an odd number of
                                        	; columns, do the odd column now
YMajorFullRunsLoop:
        mov     cx,[bp].WholeStep 	;run is at least this long
        add     dx,[bp].AdjUp   		;advance the error term and add an extra
        jnc     YMajorNoExtra   		; pixel if the error term so indicates
        inc     cx              		;one extra pixel in run
        sub     dx,[bp].AdjDown 		;reset the error term
YMajorNoExtra:
                                		;draw the run
YMajorRunLoop:
        mov     [di],al         		;draw the pixel
        add     di,SCREEN_WIDTH 		;advance along the major axis (Y)
        dec     cx
        jnz     YMajorRunLoop
        add     di,bx           		;advance along the minor axis (X)
YMajorFullRunsOddEntry:         		;enter loop here if there is an odd number
                                		; of full runs
        mov     cx,[bp].WholeStep 	;run is at least this long
        add     dx,[bp].AdjUp   		;advance the error term and add an extra
        jnc     YMajorNoExtra2  		; pixel if the error term so indicates
        inc     cx              		;one extra pixel in run
        sub     dx,[bp].AdjDown 		;reset the error term
YMajorNoExtra2:
                                		;draw the run
YMajorRunLoop2:
        mov     [di],al         		;draw the pixel
        add     di,SCREEN_WIDTH 		;advance along the major axis (Y)
        dec     cx
        jnz     YMajorRunLoop2
        add     di,bx           		;advance along the minor axis (X)

        dec     si
        jnz     YMajorFullRunsLoop
; Draw the final run of pixels.
YMajorDrawLast:
        pop     cx              		;get back the final run pixel length
YMajorLastLoop:
        mov     [di],al         		;draw the pixel
        add     di,SCREEN_WIDTH 		;advance along the major axis (Y)
        dec     cx
        jnz     YMajorLastLoop
Done:
    	pop ds  				;restore caller's DS
    	pop di
    	pop si  				;restore C register variables
    	mov sp,bp   			;deallocate local variables
    	pop bp  				;restore caller's stack frame
    	ret
_LineDraw   endp
    end

