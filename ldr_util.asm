
;;; ldr_util.asm
;;; collection of ldr_utility functions.

;;; 1. _get_ldr_data_table_entry_1(index)
;;; 2. _enumerate_ldr_data_table_entry_1(pointer to callback)
;;;   1st arg :: module index
;;;   2nd arg :: function pointer to callback
;;; 3. _enumerate_export_table_2(pointer to callback)
;;;   1st arg :: module index
;;;   2nd arg :: function pointer to callback
;;; 4.  _enumerate_import_table_2(pointer to callback)
;;;   1st arg :: module index
;;;   2nd arg :: function pointer to callback

	;; section .data
	;; no static data area as this is intented to be executed
	;; without static memory access and minimum heap access.
	;; for code injection of remote proecss.
	default rel
	section .data

_ret:	
	dq 0
	
	section .text

;;; ntdll specific function
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	
	global _get_ntdll_faddr_0
	global _get_ntdll_faddr_1
	;; get the function address from module handle
	global _get_faddr_from_modulehandle_2

	global _get_ntdll_handle_1

	global _get_faddr_by_name_3
	global _get_export_entry_from_handle_1

	global _get_findex_by_name_3
	global _get_faddr_by_index_3

	global _get_ntdll_faddr_end

;;; Generic funciton
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	global _enumerate_export_table_2
	global _enumerate_import_table_2
	
	global _get_ldr_data_table_entry_1
	global _enumerate_ldr_data_table_entry_1
	
	global _strcmp_w_case_insensitive
	global _strcmp_w_case_insensitive
	
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_enumerate_import_table_2:
	call _get_ldr_data_table_entry_1
	mov rcx,[rax+0x30]
	call _get_import_entry_from_handle_1
	;; let 3rd 2nd
	mov r8,rdx
	;; set 2nd argument
	mov rdx,rax
	call _enumerate_import_table_3
	;; mov rax,[rax]
	ret

;;; 1st :: base address
;;; 2nd ;; import entry
;;; 3rd :: pointer to callback
_enumerate_import_table_3:
	;; base of module
	mov r13,rcx
	;; heads of import table
	mov r14,rdx
	;; call back address
	mov r15,r8
;;; ;;;;;;;;; start to read each value of import descripor 
._l0:
	;; import name table entry
	mov rdi,0
	mov edi,[r14+0x00]
	;; add module base
	add rdi,r13
	;; import address table entry
	mov rsi,0
	mov esi,[r14+0x10]
	;; add module base
	add rsi,r13
	mov rbx,0
	mov ebx,[r14+0x0c]
	mov r12,rbx
	add r12,r13
._l1:
	;; import name table
	mov r8,[rdi]
	add r8,r13
	add r8,0x2
	;; import address table
	mov r9,[rsi]
	add r9,r13
	add r9,0x2

	;; if import address table & import name table points to same address,
	;; it means this is the end of an import address & name table on
	;; an image import descriptor.
	cmp r8,r9
	je _enumerate_import_table_3._l2
	mov rdx,r12
	mov rcx,r14

	sub rsp,0x20
	call r15
	add rsp,0x20
	;; increment import address table & import name table
	add qword rdi,0x8
	add qword rsi,0x8	
	jmp _enumerate_import_table_3._l1
._l2:
	add r14,0x14
	;; the end of import descriptor table is null
	cmp qword [r14],0
	jne _enumerate_import_table_3._l0
._l3:
	ret

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_enumerate_export_table_2:
	call _get_ldr_data_table_entry_1
	mov rcx,[rax+0x30]
	call _get_export_entry_from_handle_1
	;; let 3rd 2nd
	mov r8,rdx
	;; set 2nd argument	
	mov rdx,rax
	call _enumerate_export_table_3
	ret

_enumerate_export_table_3:
	;; r13 == module_base
	mov rsi,rcx
	;; head of entry directory
	mov rdi,rdx
	mov rax,0
	;; entry directory heads + 0x20 is the first export name table
	mov eax,[rdi+0x20]
	add rax,rsi
	;; r12 == index
	mov r12,0
	;; r15 [pointer to callback]
	mov r15,r8
	;; head of export name table
	mov r14,rax
	;; r13 == number of entry on name index table
	mov rbx,0
	mov ebx,[rdi+0x18]
	mov r13,rbx
._l0:
	;; 1st argument
	mov rcx,rsi
	;; 2nd arugment
	mov rdx,rdi
	;; 3rd argument[function address]
	mov r8,r12
	call _get_faddr_by_index_3

	;; as callee volatile rdi & rsi,
	;; original value needs to be reset here.
	mov rdi,rdx
	mov rsi,rcx

	;; 2nd arg
	mov rdx,rax
	
	mov rbx,0
	mov ebx,[r14+r12*4]
	add rbx,rsi
	
	;; 1st arg
	mov rcx,rbx
	
	sub rsp,0x20
	call r15	
	add rsp,0x20

	add r12,1
	cmp r12,r13
	jne _enumerate_export_table_3._l0
	mov rax,rbx
	ret

_get_ldr_data_table_entry_1:
	mov rax,[gs:0x60]
	;; access peb_led_data
	mov rax,[rax+0x18]
	;; in load order module list
	mov rax,[rax+0x10]
	jmp _get_ldr_data_table_entry_1._l1
._l0:
	mov rax,[rax+0x0]
	dec rcx
._l1:
	cmp rcx,0
	jne _get_ldr_data_table_entry_1._l0
	
	ret

;;; 1st argument :: function pointer to be called per iteration of an entry
_enumerate_ldr_data_table_entry_1:
	push rbp
	mov rbp,rsp
	mov rax,[gs:0x60]
	;; access peb_led_data
	mov rax,[rax+0x18]
	;; in load order module list
	mov rax,[rax+0x10]
	;; record first led_data_table_entry
	;; push rax
	mov r13,rax
	mov r15,rcx
	;; mov [_tmp03],rax
._l0:
	mov rax,[rax+0x0]
	mov r14,rax
	;; sub rsp,0x20
	mov rcx,rax
	call r15
	;; add rsp,0x20
._l1:
	;; ldr_data_table is circular list which means
	;; the last entry points to the head of it.
	;; if you record first one, you can recognize that you
	;; have turned around the every element of it.
	mov rax,r14
	cmp r13,rax
	jne _enumerate_ldr_data_table_entry_1._l0
	pop rbp
	ret
	
_get_base_module:
	;; mov rax, [fs:0x30] for 32bit
	mov rax,[gs:0x60]
	;; access peb_led_data
	mov rax,[rax+0x18]
	;; in load order module list
	mov rax,[rax+0x10]
	add rax,[rax+0x30]
	ret

;; ._l0:
;; 	;; r8 is the length of string
;; 	inc r8
;; 	dec rbx
;; 	mov rdx,[rbx]
;; 	;; 0x5c means "\" in ASCII.
;; 	;; that is trailing from the tail of string,
;; 	;; stamble onto the "\" which you came across at first
;; 	cmp dl,0x5c
;; 	jne _get_module_handle._l0
;; 	mov rax,rbx
;; 	add rax,2
;; 	ret

;;; this function is intended to be used for strcmp of multi-byte(2byte).
;;; 1st :: pointer to string
;;; 2nd :: pointer to string
;;; 3rd :: len
_strcmp_w_case_insensitive_3:
	mov rax,0
	mov rdi,rcx
	mov rsi,rdx
	jmp _strcmp_w_case_insensitive_3._l1
._l0:
	add rax,2
	add rdi,2
	add rsi,2
	cmp rax,r8
	je _strcmp_w_case_insensitive_3._l2
._l1:
	mov cx,[rdi]
	mov dx,[rsi]
	;; if one of three is met(which means case insensitive),
	;; go back to loop, otherwise
	cmp cx,dx
	je _strcmp_w_case_insensitive_3._l0
	mov cl,[rdi]
	mov dl,[rsi]
	mov bl,cl
	add bl,0x20
	cmp bl,dl
	je _strcmp_w_case_insensitive_3._l0
	;; mov cl,[rdi]
	;; mov dl,[rsi]
	mov bl,dl
	add bl,0x20
	cmp bl,cl

	;; mov rax,0
	;; mov al,bl
	
	je _strcmp_w_case_insensitive_3._l0
	
._l2:
	ret

_get_ntdll_faddr_0:
	db 0x48
	db 0xb8
	dq _ret
	mov rcx,rax

_get_ntdll_faddr_1:
	call _get_ntdll_handle_1
	mov rdx,rcx
	mov rcx,rax
	call _get_faddr_from_modulehandle_2
	mov rbx,[_get_ntdll_faddr_0+2]
	sub rbx,8
	mov [rbx],rax
	jmp _get_ntdll_faddr_end
	;; ret

_get_ntdll_handle_1:
	;; mov rax, [fs:0x30] for 32bit
	mov rax,[gs:0x60 ]
	mov rax,[rax+0x18]
	mov rax,[rax+0x10]
	mov rax,[rax+0x0 ]
	mov rax,[rax+0x30]
	ret

;;; rcx :: module handle
;;; rdx :: address of query string
;;; return :: function address
_get_faddr_from_modulehandle_2:
	call _get_export_entry_from_handle_1
	;; 2nd argument will be 3rd
	mov r8,rdx
	;; return value(heads of ied) will be 2nd
	mov rdx,rax
	call _get_faddr_by_name_3
	ret

_get_import_entry_from_handle_1:
	mov rax,rcx
	mov rbx,0
	mov ebx,[rax+0x3c]
	add ebx,0x90
	;; add rax,0x18 + 0x70
	mov ebx,[rax+rbx]
	add rax,rbx
	ret

_get_export_entry_from_handle_1:
	mov rax,rcx
	mov rbx,0
	mov ebx,[rax+0x3c]
	add ebx,0x88
	;; add rax,0x18 + 0x70
	mov ebx,[rax+rbx]
	add rax,rbx
	ret

_get_faddr_by_name_3:
	call _get_findex_by_name_3
	mov r8,rax
	call _get_faddr_by_index_3
	ret

;;; 3 argument
;;; 1st[rcx] :: base address of the module
;;; 2nd[rdx] :: base address of export entry directory
;;; 3rd[r8 ] :: function index
;;; return value[rax] :: function address
_get_faddr_by_index_3:
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
_get_findex_by_name_3:
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
	jb _get_findex_by_name_3._l1
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
	jb _get_findex_by_name_._l1
	sub qword r12,4
	shr r12,2
	mov rax,r12
	ret

