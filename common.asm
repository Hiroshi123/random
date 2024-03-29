
	;; section .data
	;; no static data area as this is intented to be executed
	;; without static memory access and minimum heap access.
	;; for code injection of remote proecss.
	default rel
	section .text

	global __set_args
	global _call_with_b8
	global _call_with_b8_end	
	global _call64
	
	global _get_ntdll_handle
	global _get_findex_by_name
	global _strcmp
	global _strlen
	global _get_fname_by_index
	global _get_export_entry_from_handle
	global _get_faddr_by_index
	global _get_faddr_by_name
	global _get_faddr_from_modulehandle
	global _get_ntdll_faddr_with_pre
	global _get_ntdll_faddr
	global _get_ntdll_faddr_end
	
;;; rax -> argument list address :: argument1 (contains number of arguments)
;;;     -> argument list address :: argument2 ()
;;;     -> argument list address :: argument3 ()
;;;     -> argument list address :: argument4 ()

;;; 1st[rcx] :: heap area
;;; 2nd[rdx] :: number of arguments
;;; 3rd[r8 ] :: 1st argument
;;; 4th[r9 ] :: 2nd argument
;;; any other arugments are going to be set on stack on top of shadow space(+0x20)

__set_args:
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
	jmp __set_args
_set_arg2:
	mov [rcx],r9
	sub rcx,8
	dec rdx
	jmp __set_args
_set_arg_more_than_3:
	mov rax,rdx
	sub rax,2
	shl rax,0x3
	add rax,0x20
	mov rax,[rsp+rax]
	mov [rcx],rax
	sub rcx,8
	dec rdx
	jmp __set_args


;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	
_call_with_b8:
	db 0x48
	db 0xb8
	dq 0
_call64:
	push rbp
	;; get the value of arg num
	mov rsi,[rax]
	;; mov rbp,rsp

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
	jbe _call64._l2

	add rax,0x8	
	mov r12,[rax]
	lock xchg [rdi],r12
	;; mov r13,r12
	mov [rax],r12
	dec rsi
	add rdi,0x08
	jmp _call64._l1

._l2:	
	sub rsp,0x20
	
	add rax,0x8
	call [rax]
	
	add rsp,0x20
	
	mov qword rcx,[_call_with_b8+2]
	mov rsi,[rcx]
	;; return value is going to be set on heads 8bytes of allocation
	;; note argnum needs to be preserved on caller.
	mov [rcx],rax
	
	add rcx,0x20
	mov rdi,rsp
	
._l3:
	cmp rsi,0x4
	jbe _call64._l4

	add rcx,0x08
	mov rdx,[rcx]
	mov [rdi],rdx
	dec rsi
	add rdi,0x08
	jmp _call64._l3
._l4:
	pop rbp
_call_with_b8_end:
	ret

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	
_get_ntdll_faddr_with_pre:
	db 0x48
	db 0xb8
	dq 0
	mov rcx,rax

_get_ntdll_faddr:
	call _get_ntdll_handle
	mov rdx,rcx
	mov rcx,rax
	call _get_faddr_from_modulehandle
	mov rbx,[_get_ntdll_faddr_with_pre+2]
	sub rbx,8
	mov [rbx],rax
	jmp _get_ntdll_faddr_end
	;; ret

_get_ntdll_handle:
	;; mov rax, [fs:0x30] for 32bit
	mov rax,[gs:0x60]
	mov rax,[rax+0x18]
	mov rax,[rax+0x10]
	mov rax,[rax+0x10]
	mov rax,[rax+0x20]
	ret

;;; rcx :: module handle
;;; rdx :: address of query string
;;; return :: function address
_get_faddr_from_modulehandle:
	call _get_export_entry_from_handle
	;; 2nd argument will be 3rd
	mov r8,rdx
	;; return value(heads of ied) will be 2nd
	mov rdx,rax
	call _get_faddr_by_name
	ret
	
_get_export_entry_from_handle:
	mov rax,rcx
	mov rbx,0
	mov ebx,[rax+0x3c]
	add ebx,0x88
	;; add rax,0x18 + 0x70
	mov ebx,[rax+rbx]
	add rax,rbx
	ret

_get_faddr_by_name:
	call _get_findex_by_name
	mov r8,rax
	call _get_faddr_by_index
	ret

;;; 3 argument
;;; 1st[rcx] :: base address of the module
;;; 2nd[rdx] :: base address of export entry directory
;;; 3rd[r8 ] :: function index
;;; return value[rax] :: function address
_get_faddr_by_index:
	mov rdi,0
	mov rsi,0
	;; directory entry + 0x1c (address of functions,[4byte])
	mov edi,[rdx+0x1c]
	;; directory entry + 0x24 (address of ordinals [4byte])
	mov esi,[rdx+0x24]
	;; add module base as they are relative.
	add rdi,rcx
	add rsi,rcx
	;; from function index to function ordinal
	shl r8,1
	mov rbx,0
	mov bx,[rsi+r8]
	;; from function ordinal to function address
	shl rbx,2
	mov rax,0
	mov eax,[rdi+rbx]
	add rax,rcx
	;;
	ret
	
_get_fname_by_index:
	mov rax,rcx
	mov r11,rcx
	mov rbx,0
	mov ebx,[rax+0x3c]
	add ebx,0x88
	;; add rax,0x18 + 0x70
	mov ebx,[rax+rbx]
	add rax,rbx
	mov ebx,[rax+0x20]
	add rbx,rcx
	mov rax,rbx

	shl rdx,2
	mov rbx,0
	mov ebx,[rax+rdx]
	add rbx,rcx
	mov rax,rbx
	ret

;;; 1st :: module base
;;; 2nd :: heads of iet
;;; 3rd :: query string(funciton name)
;;; note that r11-r15 is inconsistent against the procedure on _strcmp.
_get_findex_by_name:
	;; module base
	mov r11,rcx
	;; head of entry directory
	mov r10,rdx
	mov rax,0
	mov eax,[r10+0x20]
	add rax,r11
	mov r13,rax
	;; query string
	mov r14,r8
	;; index which will be incremeted & returned finally
	mov r12,0x00
	;; first argument [string]
	mov rcx,r14
	;; length of query string
	call _strlen	
	mov r15,rax
._l1:
	mov rbx,0
	mov ebx,[r13+r12]
	add rbx,r11
	mov rcx,r14
	mov rdx,rbx
	;; note that length of entry is just 4.
	add qword r12,4
	call _strcmp
	;; if the string is matched till the end of the length,
	;; then go out of this loop.
	cmp rax,r15
	jb _get_findex_by_name._l1
	;; subtract next addition
	sub qword r12,4
	;; get the quarter of it.
	shr r12,2
	;; return 1-index value.
	;; inc r12
	mov rax,r12
	;; restore argument
	mov rcx,r11
	mov rdx,r10
	mov r8,r14
	ret

;;; rcx,rdx,r8
_strcmp:
	mov rax,0
	mov rdi,rcx
	mov rsi,rdx
._l0:
	mov rcx,[rdi]
	mov rdx,[rsi]
	cmp rcx,rdx
	jne _strcmp._l1
	add rax,8
	add rdi,8
	add rsi,8	
	jmp _strcmp._l0
._l1:
	cmp ecx,edx
	jne _strcmp._l2
	add rax,4

	add rdi,4
	add rsi,4
	mov rcx,[rdi]
	mov rdx,[rsi]
._l2:
	cmp cx,dx
	jne _strcmp._l3
	add rax,2
	add rdi,2
	add rsi,2
	mov rcx,[rdi]
	mov rdx,[rsi]	
._l3:
	cmp cl,dl
	jne _strcmp._l4
	add rax,1
._l4:
	ret

_strlen:
	mov rax,0
._l1:
	mov bl,[rcx]
	cmp bl,0
	je _strlen._l2
	add rax,1
	add qword rcx,1
	jmp _strlen._l1
._l2:
	ret

_get_ntdll_faddr_end:
	ret
	
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; some extra stuff     ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	
_get_findex_by_name_:
	mov rax,rcx
	mov r11,rcx
	mov rbx,0
	mov ebx,[rax+0x3c]
	add ebx,0x88
	;; add rax,0x18 + 0x70
	mov ebx,[rax+rbx]
	add rax,rbx
	mov ebx,[rax+0x20]
	add rbx,rcx
	mov rax,rbx

	;; get A_SHAFinal
	mov r12,0x00
	mov r13,rax
	mov r14,rdx
	mov rcx,rdx
	call _strlen	
	mov r15,rax
._l1:
	mov rbx,0
	mov ebx,[r13+r12]
	add rbx,r11
	mov rcx,rbx
	mov rdx,r14
	add qword r12,4
	call _strcmp
	cmp rax,r15
	jb _get_findex_by_name._l1
	sub qword r12,4
	shr r12,2
	mov rax,r12
	ret

