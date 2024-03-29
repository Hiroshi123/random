
#include <windows.h>
#include <ntdef.h>
#include <stdio.h>
#include <stdint.h>

/* #define DEBUG */

extern uint64_t _call_with_b8(uint64_t);
extern void _call_with_b8_end();

extern void* _get_ntdll_handle();
//
extern void* _get_findex_by_name(void*,void*,void*);
extern void* _get_fname_by_index(void*,void*);
extern void* _get_faddr_by_index(void*,void*,void*);
extern void* _get_faddr_by_name(void*,void*,void*);

extern void* _strcmp(void*,void*);
extern void* _strlen(void*);
extern void* _get_export_entry_from_handle(void*);
extern void* _get_faddr_from_modulehandle(void*,void*);
extern void* _get_ntdll_faddr_with_pre();
extern void* _get_ntdll_faddr(void*);
extern void* _get_ntdll_faddr_end();

// should be larger than longest ansi string which appears on ntdll
// needs to be set as number of modular 8 for memory access
static const int MEMORY_SIZE_FOR_STR = 0x8 * 10;

int INJECT_OTHER_PROCESS = 1;

typedef struct {
  // does not need to be pointer as remote address cannot access via pointer.
  uint64_t addr;
  uint64_t next;
} memory_list;

memory_list MEMORY_ROOT = {};
uint64_t* CURRENT_POINTER;

static void __attribute__((constructor))
set_remote_mem(void)
{
  CURRENT_POINTER = &MEMORY_ROOT;
}

// no heap management for own process as they are freed by itself when a process is terminated.
// just for remote one.
static void __attribute__((destructor))
deallocate_remote_mem(void)
{
  if (INJECT_OTHER_PROCESS) {
    memory_list* mem = MEMORY_ROOT.next;
    void* tmp;
    while (mem) {
#ifdef DEBUG
      printf("next:%p\n",mem->next);
      printf("addr:%p\n",mem->addr);
#endif
      tmp = mem;
      mem = mem->next;
      free(tmp);
    }
  }
}

void remote_alloc(void* p) {
  memory_list* mem = malloc(sizeof(memory_list));
  memory_list* pre = (memory_list*)CURRENT_POINTER;
  pre->next = mem;
  mem->addr = p;
  mem->next = 0;
  CURRENT_POINTER = mem;
}

void* replace_query(void* process, char* query, uint8_t* s) {

  void* remote_addr = s;
  if (INJECT_OTHER_PROCESS) {
    s = malloc(MEMORY_SIZE_FOR_STR);
  }
  int8_t* _e1 = s + strlen(query);
  uint8_t* _e2 = s + MEMORY_SIZE_FOR_STR;
  uint8_t* _s = s;
  // copy data itself
  uint8_t* _str = query;
  for (;s<_e2;s++,_str++)
    *s = (s<_e1) ? *_str : 0;
  
  if (INJECT_OTHER_PROCESS) {    
    uint64_t bytesWritten;
    if (!WriteProcessMemory(process, remote_addr, _s, MEMORY_SIZE_FOR_STR, &bytesWritten)) {
      printf("error\n");
    }
    free(s);
  }
}

void* get_ntdll_faddr(void* process, char* query, uint64_t* data_begin) {

  // address where return value will be written + AnsiString()
  // allocate enough size for allocation of ansi function string name for replacement to longer one,
  int memory_for_str = MEMORY_SIZE_FOR_STR;// (strlen(query) + 1 + 7) & 0xfffffff8;
  int data_bytes = memory_for_str + 8;
  uint8_t* pc = _get_ntdll_faddr_with_pre;
  uint8_t* code = pc;
  uint8_t* e = _get_ntdll_faddr_end + 1;
#ifdef DEBUG
  printf("code len:%d\n",e - pc);
#endif
  int code_bytes = e - pc;
  // As there is only few bytes for data, data is merged on code(executable section)
  int total_bytes = data_bytes + code_bytes;
  uint8_t* data_code =
    VirtualAllocEx
    (GetCurrentProcess(), NULL, total_bytes ,MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
  uint8_t* remote_data_code;
  if (process != GetCurrentProcess()) {
    remote_data_code =
      VirtualAllocEx(process, NULL, total_bytes ,MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    remote_alloc(remote_data_code);
  }
  uint8_t* s = data_code;
  uint8_t* str_addr = s + 8;
  uint64_t diff = remote_data_code - data_code;  
  // for the time being, set it 0
  if (INJECT_OTHER_PROCESS) {
    *(uint64_t*)s = 0;
  } else {
    *(uint64_t*)s = 0;
  }
  s+=8;
  uint8_t* _e1 = s + strlen(query);
  uint8_t* _e2 = s + memory_for_str;
  // copy data itself
  uint8_t* _str = query;
  for (;s<_e2;s++,_str++)
    *s = (s<_e1) ? *_str : 0;
  void* code_on_memory = (process != GetCurrentProcess()) ? s + diff : s;  
  // copy code on local memory which is executable & writable.
  for (;pc<e;pc++,s++) {
    if (code+2 == pc) {
      *(uint64_t*)s = (process != GetCurrentProcess()) ? str_addr + diff : str_addr;
      pc += 8;
      s  += 8;
    }
    *s = *(uint8_t*)pc;
  }
  
  if (INJECT_OTHER_PROCESS) {
    uint64_t bytesWritten;
    if (!WriteProcessMemory(process, remote_data_code, data_code, total_bytes, &bytesWritten)) {
      printf("error\n");
    }
    if (!VirtualFree(data_code,0,MEM_RELEASE)) {
      printf("could not free for some reason\n");
    }
    *data_begin = remote_data_code;
    return code_on_memory;
  } 
  *data_begin = data_code;
  return code_on_memory;// data_code;
}

void* check_result(void* process, void* remote_addr) {
  
  void* local_addr = malloc(8);
  if (!ReadProcessMemory(process, remote_addr, local_addr, 8, NULL)) {
    printf("read process memory error\n");
  }
  return local_addr;
}

void* prepare_data_createfile(void* process, void* f1) {
  
  wchar_t _buf[] = L"myfile";
  uint8_t strlen = (wcslen(_buf) * 2 + 2 + 7) & 0xf8;
  uint64_t len = 11;
  uint64_t total_data_bytes =
    8*(len + 2) + // len
    sizeof(UNICODE_STRING) + // arg3(object_attributes)
    strlen + // +// arg3(object_attributes)
    sizeof(OBJECT_ATTRIBUTES) + // arg3(object_attributes)
    8 + // arg1
    16; // arg4
  
  uint8_t* data =
    VirtualAllocEx(GetCurrentProcess(), NULL, total_data_bytes ,MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
  memset(data,0,total_data_bytes);
  uint8_t* remote_data;
  if (INJECT_OTHER_PROCESS) {
    remote_data = VirtualAllocEx(process, NULL, total_data_bytes ,MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    remote_alloc(remote_data);
  }
  // not sure if it works out when a value is negative..
  uint64_t diff = remote_data - data;
  // uint64_t diff_ = data - remote_data;
  
  // pointer preparation
  uint64_t* _p = data;
  uint32_t offset = 8 * (len + 2);
  UNICODE_STRING* _d1 = data + offset;
  offset += sizeof(UNICODE_STRING);
  uint8_t* _buf10 = data + offset;
  offset += strlen;
  //((wcslen(_buf) * 2) + 7) & 0xfffffff8; //8; //(wcslen(_buf) * 2 + 7) % 8;
  OBJECT_ATTRIBUTES* _obj = data + offset;
  offset += sizeof(OBJECT_ATTRIBUTES);
  void* _file = data + offset;
  offset += 8;
  void* _io_status_block = data + offset;
  
  // when you assign pointer, if you execute it on remote process,
  // the difference of pointer needs to be taken into account.

  // every assignment on local variable should be neglected.
  // the assignment which is on argument tree needs to be considered.
  
  memcpy(_buf10,_buf,wcslen(_buf) * 2 );
  
  _d1->Length = (wcslen(_buf) * 2);
  _d1->MaximumLength = (wcslen(_buf) * 2) + 2;
  _d1->Buffer = (INJECT_OTHER_PROCESS) ? _buf10 + diff : _buf10;
  
  //
  _obj->Length = sizeof(OBJECT_ATTRIBUTES);
  _obj->RootDirectory = 0x50;//NULL;
  _obj->ObjectName = (INJECT_OTHER_PROCESS) ? (uint8_t*)_d1 + diff : _d1; 
  _obj->Attributes = 0x40;//NULL;
  _obj->SecurityDescriptor = 0;//NULL;
  _obj->SecurityQualityOfService = 0;//NULL;
  //

  // file,obj,io_status_block
  if (INJECT_OTHER_PROCESS) {
    __set_args(_p+len,len,
	       (uint8_t*)_file + diff,
	       0x40100080,
	       (uint8_t*)_obj + diff,
	       (uint8_t*)_io_status_block + diff,
	       0,0x80,7,5,0x60,0,0);
  } else {
    __set_args(_p+len,len,_file,0x40100080,_obj,_io_status_block,0,0x80,7,5,0x60,0,0);
  }  
  *_p = len;
  *(_p+1+len) = f1;
  /* uint64_t* d = data; */
  /* uint64_t* e = 16 + _io_status_block; */
  /* for (;d<e;d++) { */
  /*   printf("%p,%x,%p\n",d,*d,*d); */
  /* } */
  
  if (process != GetCurrentProcess()) {
    /* uint8_t* remote_data; */
    /* remote_data = VirtualAllocEx(process, NULL, total_data_bytes ,MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE); */    
    uint64_t bytesWritten;
    if (!WriteProcessMemory(process, remote_data, data, total_data_bytes, &bytesWritten)) {
      printf("error\n");
    }
    if (!VirtualFree(data,0,MEM_RELEASE)) {
      printf("could not free for some reason\n");
    }
    return remote_data;
  }
  // 0b11111000
  /* printf("!%x,%x,%x\n",wcslen(_buf) * 2, strlen, ((wcslen(_buf) * 2) + 7) & 0xfffffff8); */
  return data;
}

void* prepare_data_ldrloaddll(void* process, void* f1, wchar_t* buf10) {

  uint8_t strlen = MEMORY_SIZE_FOR_STR;// (wcslen(buf10) * 2 + 2 + 7) & 0xf8;
  uint64_t len = 4;
  uint64_t total_data_bytes =
    8*(len + 2) + // len
    8 + // arg2
    sizeof(UNICODE_STRING) + // arg3
    strlen + // +// arg3
    8; // arg4
  
  uint8_t* data =
    VirtualAllocEx(GetCurrentProcess(), NULL, total_data_bytes ,MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
  if (!data) {
    printf("allocation error\n");
  }
  memset(data,0,total_data_bytes);  
  uint8_t* remote_data = 0;
  if (INJECT_OTHER_PROCESS) {
    remote_data = VirtualAllocEx(process, NULL, total_data_bytes ,MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    remote_alloc(remote_data);
  }
  uint64_t diff = remote_data - data;
  
  uint64_t* p = data;
  int offset = 8 * (len + 2);
  uint64_t* arg2_flags = data + offset;
  offset += 8;
  UNICODE_STRING* arg3_unicode = (UNICODE_STRING*)(data+offset);
  offset += sizeof(UNICODE_STRING);
  uint8_t* arg3_str = data + offset;
  offset += strlen;
  uint64_t* arg4 = data + offset;
  
  *arg2_flags = 0;//LOAD_WITH_ALTERED_SEARCH_PATH;
  // LOAD_LIBRARY_SEARCH_SYSTEM32;
  // LOAD_WITH_ALTERED_SEARCH_PATH;
  // LOAD_LIBRARY_SEARCH_SYSTEM32;
  // LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR;
  // 
  //LOAD_LIBRARY_SEARCH_DEFAULT_DIRS;
  //LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR;
  //LOAD_WITH_ALTERED_SEARCH_PATH;// LOAD_LIBRARY_SEARCH_DEFAULT_DIRS;
  //LOAD_WITH_ALTERED_SEARCH_PATH;//IMAGE_FILE_EXECUTABLE_IMAGE;
  
  memcpy(arg3_str,buf10,wcslen(buf10) * 2 );
  
  arg3_unicode->Length = (wcslen(buf10) * 2);
  arg3_unicode->MaximumLength = (wcslen(buf10) * 2) + 2;
  arg3_unicode->Buffer = (INJECT_OTHER_PROCESS) ? arg3_str + diff : arg3_str;
  *arg4 = 0;// INVALID_HANDLE_VALUE;
  if (INJECT_OTHER_PROCESS) {
    __set_args
      (p+len, len,       
       1,
       (uint8_t*)arg2_flags + diff,
       (uint8_t*)arg3_unicode + diff,
       (uint8_t*)arg4 + diff
       );
  } else {
    __set_args
      (p+len, len,
       1,
       arg2_flags,
       arg3_unicode,
       arg4
       );
  }
  *p = len;
  *(p+1+len) = f1;
  if (INJECT_OTHER_PROCESS) {
    uint64_t bytesWritten;
    if (!WriteProcessMemory(process, remote_data, data, total_data_bytes, &bytesWritten)) {
      printf("error\n");
    }
    if (bytesWritten != total_data_bytes) {
      printf("bytes not written:%d\n",total_data_bytes - bytesWritten);
    }
    if (!VirtualFree(data,0,MEM_RELEASE)) {
      printf("could not free for some reason\n");
    }
    return remote_data;
  }
  return data;
}

void* prepare_data_ldrgetprocadr(void* process, void* f1, void* moduleHandle, char* fname) {

  uint64_t len = 4;
  uint8_t _strlen = MEMORY_SIZE_FOR_STR;// (strlen(fname) + 8) & 0xf8;  
  uint64_t total_data_bytes =
    8*(len + 2) + // len
    8 + // arg1
    sizeof(ANSI_STRING) + // arg2(NT_STRING)
    _strlen + // arg2(ansi str)
    0 + //arg3
    8; // arg4
#ifdef DEBUG
  printf("data:%d\n",total_data_bytes);
#endif
  uint8_t* data =
    VirtualAllocEx(GetCurrentProcess(), NULL, total_data_bytes ,MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
  if (!data) {
    printf("allocation error\n");
  }
  memset(data,0,total_data_bytes);
  uint8_t* remote_data;
  if (process != GetCurrentProcess()) {
    remote_data = VirtualAllocEx(process, NULL, total_data_bytes ,MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    remote_alloc(remote_data);
  }
  uint64_t diff = remote_data - data;
  
  uint64_t* p = data;
  int offset = 8 * (len + 2);
  uint64_t* arg1 = data + offset;
  offset += 8;
  ANSI_STRING* arg2_nt_str = data + offset;
  offset += sizeof(ANSI_STRING);
  uint8_t* arg2_str = data + offset;
  offset += _strlen;
  uint64_t* arg4 = data + offset;

  *arg1 = moduleHandle;  
  memcpy(arg2_str,fname,strlen(fname));
  arg2_nt_str->Length = strlen(fname);
  arg2_nt_str->MaximumLength = strlen(fname) + 2;
  if (process != GetCurrentProcess()) {
    arg2_nt_str->Buffer = arg2_str + diff;
  } else {
    arg2_nt_str->Buffer = arg2_str;
  }
  *arg4 = 0;
  if (INJECT_OTHER_PROCESS) {
    __set_args
      (p+len, len,
       moduleHandle,// (uint8_t*)*arg1 + diff,//module handle
       (uint8_t*)arg2_nt_str + diff,//
       0,// ordinal
       (uint8_t*)arg4 + diff // out funciton address
       );
  } else {
    __set_args
      (p+len, len,
       *arg1,//module handle
       arg2_nt_str,//
       0,// ordinal
       arg4 // out funciton address
       );
  }
  *p = len;
  *(p+1+len) = f1;
  if (INJECT_OTHER_PROCESS) {
    uint64_t bytesWritten;
    if (!WriteProcessMemory(process, remote_data, data, total_data_bytes, &bytesWritten)) {
      printf("error\n");
    }
    if (bytesWritten != total_data_bytes) {
      printf("bytes not written:%d\n",total_data_bytes - bytesWritten);
    }
    if (!VirtualFree(data,0,MEM_RELEASE)) {
      printf("could not free for some reason\n");
    }
    return remote_data;
  }
  return data;
}

void* prepare_code(void* process, void* p) {

  uint8_t* pc = _call_with_b8;
  uint8_t* e = _call_with_b8_end+1;
  uint64_t bytesN = e-pc;
#ifdef DEBUG
  printf("byte:%x\n",e-pc);
#endif
  // code preparation
  uint8_t* s = VirtualAllocEx(GetCurrentProcess(), NULL, bytesN, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
  uint8_t* code = s;
  for (;pc<e;pc++,s++) {
    if (code+2 == s) {
      *(uint64_t*)s = p;
      pc += 8;
      s  += 8;
    }
    *s = *(uint8_t*)pc;
  }
  if (INJECT_OTHER_PROCESS) {
    uint8_t* remote_code;
    remote_code = VirtualAllocEx(process, NULL, bytesN ,MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    remote_alloc(remote_code);
    uint64_t bytesWritten;
    if (!WriteProcessMemory(process, remote_code, code, bytesN, &bytesWritten)) {
      printf("error\n");
    }
    if (bytesWritten != bytesN) {
      printf("bytes not written:%d\n",bytesN - bytesWritten);
    }
    if (!VirtualFree(code,0,MEM_RELEASE)) {
      printf("could not free for some reason\n");
    }
    return remote_code;
  }
  return code;
}

void exec(void* process, void* code) {
  if (!INJECT_OTHER_PROCESS) {
    asm("call *%0" : : "r"(code));
  } else {
    void* remote_thread = CreateRemoteThread(process, NULL, 0, code, NULL, 0 , NULL);
    if (!remote_thread) {
      printf("thread creation error\n");
    }
    WaitForSingleObject(remote_thread, INFINITE);
    /* if (!WaitForSingleObject(remote_thread, INFINITE)) { */
    /*   printf("error on remote,%x\n",GetLastError()); */
    /* } */
    CloseHandle(remote_thread);
  }
}

BOOL memory_free(void* process, void* data, void* code) {
  BOOL res1 = VirtualFreeEx(process, data, 0, MEM_RELEASE);
  BOOL res2 = VirtualFreeEx(process, code, 0, MEM_RELEASE);
  return res1 && res2;
}

BOOL EnablePrivileges(LPTSTR lpPrivilegeName, BOOL bEnable)
{
  HANDLE hToken;
  LUID luid;
  TOKEN_PRIVILEGES tokenPrivileges;
  BOOL bRet;
  bRet = OpenProcessToken
    (GetCurrentProcess(),
     TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY,
     &hToken);
  if (!bRet) {
    return FALSE;
  }  
  bRet = LookupPrivilegeValue(NULL, lpPrivilegeName, &luid);
  if (bRet) {
    
    tokenPrivileges.PrivilegeCount = 1;
    tokenPrivileges.Privileges[0].Luid = luid;
    tokenPrivileges.Privileges[0].Attributes = bEnable ? SE_PRIVILEGE_ENABLED : 0;
    AdjustTokenPrivileges
      (hToken,
       FALSE,
       &tokenPrivileges,
       0,// bufferLen
       0,// PreviousState
       0);// Return Len
    // NtAdjustPrivilegesToken    
    bRet = GetLastError() == ERROR_SUCCESS;
  }
  CloseHandle(hToken);
  printf("ret:%x\n",bRet);
  return bRet;
}

void set_faddr_with_no_arg(uint64_t* p, void* f1) {
  // even though no argument, pretend to have at least 4 argv
  int len = 4;
  *p = len;
  // function address is set to here
  *(p+1+len) = f1;  
}

int main(int argc, char** argv) {
  
  EnablePrivileges(SE_DEBUG_NAME, TRUE);
  wchar_t* dllname = malloc(40);
  void* process;
  if (argc != 3) {
    printf("usage\n");
    printf("first argument : DLL to be injected.\n");
    printf("second arugment ; pid that DLL will be injected. 64bit only. For own process, own\n");
    printf("e.g. injector.exe ex01.dll own -> inject ex01 to own process\n");
    return 1;
  } else {
    dllname = argv[1];    
    if (!strcmp(argv[2],"own")) {
      printf("treat it as own process injection.\n");
      process = GetCurrentProcess();
      INJECT_OTHER_PROCESS = 0;
    } else {
      process = OpenProcess(PROCESS_ALL_ACCESS,FALSE,atoi(argv[2]));
      INJECT_OTHER_PROCESS = 1;
      if (!process) {
	printf("pid:%d not found or cant open\n",atoi(argv[2]));
	return 1;
      }
    }
  }
  printf("inject subject process:%p\n",process);
  
  char* query1 = "LdrLoadDll";
  uint64_t* data_begin = malloc(8);
  
  uint64_t* c = get_ntdll_faddr(process, query1, &data_begin);
  exec(process, c);
  uint64_t* ret = check_result(process,data_begin);
  void* ldrloaddll_addr = *(uint64_t*)ret;  
  char* query2 = "LdrGetProcedureAddress";

  // as writeprocessmemory does not allow rewrite on the pre-written memory,
  // map the same function again...
  if (INJECT_OTHER_PROCESS) {
    c = get_ntdll_faddr(process, query2, &data_begin);
  } else {
    replace_query(process, query2, data_begin + 1);
  }
  exec(process, c);
  ret = check_result(process,data_begin);
  void* ldrgetproc_addr = *(uint64_t*)ret;  
  // uint8_t* data = prepare_data_createfile(process, *(uint64_t*)ret);
  
  uint8_t* data = prepare_data_ldrloaddll(process, ldrloaddll_addr, dllname);  
  void* code = prepare_code(process, data);
  exec(process, code);
  void* moduleHandle;
  if (*(uint64_t*)(check_result(process,data)) == 0) {
#ifdef DEBUG 
    printf("NTSTATUS:0,ok!\n");
#endif
    uint64_t* arg4 = check_result(process, data + 8*(4 + 2) + 8 + sizeof(UNICODE_STRING) + MEMORY_SIZE_FOR_STR);
#ifdef DEBUG 
    printf("returned module handle:%p,%p\n",*arg4,arg4);
#endif
    moduleHandle = *arg4;
  }
  /* printf("ldrgetpro:%p,%p\n",ldrgetproc_addr,moduleHandle); */
  data = prepare_data_ldrgetprocadr(process, ldrgetproc_addr, moduleHandle, "init");
  code = prepare_code(process, data);
  exec(process, code);
  uint64_t* faddr =
    check_result(process,(uint64_t*)(data + 8*(4 + 2) + 8 + sizeof(ANSI_STRING) + MEMORY_SIZE_FOR_STR));
  // set_faddr_with_no_arg(data, *arg4);
  exec(process, *faddr);
}

