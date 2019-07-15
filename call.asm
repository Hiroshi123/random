;;; x64 MS calling convention
;;; to call the function which was written by microsoft in x64 (including system call),
;;; you need to set a stack and argument properly.
;;; Following is how to call them depending on argument.
;;; 1. function which has less than 4 arguments.
;;;    [register]
;;;    1st argument => rcx
;;;    2nd argument => rdx
;;;    3rd argument => r8
;;;    4th argument => r9
;;; 
;;;    [caution]
;;;    if arguments are floating point, used register is different.
;;;    refer to MS document for further info.
;;; 
;;;    [stack]
;;;    shadow space(0x20 bytes) needs to be preserved 
;;;    e.g.
;;;    push rbp
;;;    mov  rsp,20
;;;    call 
;;;    mov  rsp,20
;;;    pop  rbp
;;;
;;; 2. function which has more than 5 arguments.
;;; 
;;;    [register]
;;;    same
;;;
;;;    [stack]
;;;    arguments are put on stack after shadow space(NOT BELOW!!!).
;;;    no stack extension is needed.
;;;    0x7ffc0000 (shadow space)
;;;    0x7ffc0008 (shadow space)
;;;    0x7ffc0010 (shadow space)
;;;    0x7ffc0018 (shadow space)
;;;    0x7ffc0020 (5th argument/ previously set rbp(after push rbp))
;;;    0x7ffc0028 (6th argument/ previously set rip)
;;;    0x7ffc0030 (7th argument/ some data on caller)
;;;    0x7ffc0038 (8th )
;;;    ....(more arguments, more placement)
;;;
;;;    [Caution]
;;;    Values on address on which arguments was put needs to be stored on somewhere else.
;;;    especially, if you did not restore rip, you cannot come back where you came from.
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; call utility 
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Function
;;; 1. call64_1(pointer to data_area($1))
;;; 2. call64_2(argnum.faddr) :
;;; -> allows to set the arguments on static area.
;;; 3. call64_0
;;; -> intended to be used with remote code injection with no arguments.
;;;    0x48 0xb9 + (8byte) means mov rcx (8byte).
;;;    by filling 8byte as you like which points data_area,
;;;    you do not need to set rcx as an argument.
;;; 
;;; $1 [data_area]
;;; heap or static data area. If it is for remote code injection, use heap,
;;; otherwise, use static for simplicity.
;;; 
;;; 0xxxxx0000 (argnum/ret)
;;; 0xxxxx0008 (function address)
;;; 0xxxxx0010 (1st arugment)
;;; 0xxxxx0018 (2nd arugment)
;;; 0xxxxx0020 (3rd arugment)
;;; .. (incremented depends on number of arguments)

;;; Functionality
;;; 1. useful for code injection by createRemoteThread
;;; -> No initial requirement for register assignment.
;;; -> Memory on which program access for argumnet retrieval depends on just 1 argument.
;;; -> return value is written on the memory where initially argnum is written.
;;;    return value is passed on rax. For getting result of remote code, the value on rax
;;;    is copied on the beginning of data_area.
;;;    [Internal]
;;;      After calling had been done, program will take a look at instruction pointer
;;;      where call64_0 starts plus 2.
;;;      This area points to heads of data_area on either static area or heap area.
;;;      A value on rax is saved on this address.
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	section .data
	default rel
	global _argnum
	global _ret
	global _f_addr
	global _arg1
	global _arg2
	global _arg3
	global _arg4
	global _arg5
	global _arg6
	global _arg7
	global _arg8
	global _arg9
	global _arg10
	global _arg11

_argnum:
_ret:	
	dq 0
_f_addr:
	dq 0
_arg1:
	dq 0
_arg2:
	dq 0
_arg3:
	dq 0
_arg4:
	dq 0
_arg5:
	dq 0
_arg6:
	dq 0
_arg7:
	dq 0
_arg8:
	dq 0
_arg9:
	dq 0
_arg10:
	dq 0
_arg11:
	dq 0
_arg12:
	dq 0
_arg13:
	dq 0
_arg14:
	dq 0
_arg15:
	dq 0
	
	section .text
	global _call64_0
	global _call64_1
	global _call64_2
	global _call64_end	
	global _set_args
	;; for debug
	global _call64_less_than4_arg
	
_call64_less_than4_arg:
	push rbp
	sub rsp,0x20
	mov r9,[_arg4]
	mov r8,[_arg3]
	mov rdx,[_arg2]
	mov rcx,[_arg1]
	mov r10,rcx
	call [_f_addr]
	mov [_ret],rax
	add rsp,0x20
	pop rbp
	ret

;;; used when setting arugments on data_area such as heap.
;;; 1st[rcx] :: pointer to highest data area
;;; 2nd[rdx] :: number of arguments
;;; 3rd[r8 ] :: 1st argument
;;; 4th[r9 ] :: 2nd argument
;;; any other arugments are going to be set on stack on top of shadow space(+0x20)
_set_args:
	cmp rdx,0
	je _done
	cmp rdx,1
	je _set_arg1
	cmp rdx,2
	je _set_arg2
	jmp _set_arg_more_than_3
_done:
	ret
_set_arg1:
	mov [rcx],r8
	sub rcx,8	
	dec rdx
	jmp _set_args
_set_arg2:
	mov [rcx],r9
	sub rcx,8
	dec rdx
	jmp _set_args
_set_arg_more_than_3:
	mov rax,rdx
	sub rax,2
	shl rax,0x3
	add rax,0x20
	mov rax,[rsp+rax]
	mov [rcx],rax
	sub rcx,8
	dec rdx
	jmp _set_args

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; _call64_2(argnum/function_addrress)
;;; assumed to be used when arguments are set on static area(not remote code injection)
;;; usage :: e.g. _call64_2(4,0x40004890)
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_call64_2:
	lea rax,[_argnum]
	mov [rax],rcx
	mov [rax+8],rdx
	jmp _call64_base

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; _call64_1
;;; can be used where arguments on static area or heap area.
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
_call64_1:
	mov rax,rcx
	jmp _call64_base

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; _call64_0
;;; 8bytes of instruction pointer + 2 should be written as pointer to allocated area when it is used.
;;; intended to be used for remote code injection.
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_call64_0:
	db 0x48
	db 0xb8
	dq _ret
;;; argument preparation internal
_call64_base:
	push rbp
	;; get the value of arg num
	mov rsi,[rax]
	;; preserve function address
	add rax,0x8
	mov rbx,[rax]
	;; 1st arugment
	add rax,0x8
	mov rcx,[rax]
	;; 2nd argument
	add rax,0x8
	mov rdx,[rax]
	;; 3rd argument	
	add rax,0x8
	mov r8,[rax]
	;; 4th argument
	add rax,0x8
	mov r9,[rax]
	mov rdi,rsp
._l1:
	cmp rsi,0x4
	jbe _call64_base._l2

	add rax,0x8	
	mov r12,[rax]

	lock xchg [rdi],r12
	mov [rax],r12
	dec rsi
	add rdi,0x08
	jmp _call64_base._l1
._l2:
	sub rsp,0x20	
	call rbx
	add rsp,0x20
	mov qword rcx,[_call64_0+2]
	mov rsi,[rcx]
	;; return value is going to be set on heads 8bytes of allocation
	;; note argnum needs to be preserved on caller.
	mov [rcx],rax
	;; skip argnum/faddr/arg1-4/
	add rcx,0x28
	mov rdi,rsp
._l3:
	cmp rsi,0x4
	jbe _call64_base._l4
	add rcx,0x08
	mov rdx,[rcx]
	mov [rdi],rdx
	dec rsi
	add rdi,0x08
	jmp _call64_base._l3
._l4:
	pop rbp
;;; in case code copied on heap, _call64_0_end + 1 means last of it.
_call64_0_end:
	ret

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	