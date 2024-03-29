

#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <winternl.h>
#include <wchar.h>

extern uint64_t _call64_2();

extern uint64_t* _ret;
extern uint64_t* _arg1;
extern uint64_t* _arg2;
extern uint64_t* _arg3;
extern uint64_t* _arg4;
extern uint64_t* _arg5;


char test1() {
  void* m = GetModuleHandle("ntdll");
  void* f = GetProcAddress(m,"RtlInitUnicodeString");
  UNICODE_STRING* file = malloc(sizeof(UNICODE_STRING));
  char* ole = L"ole32.dll";
  _arg1 = file;
  _arg2 = ole;
  _call64_2(2, f);
  printf("NTSTATUS:%p\n",_ret);
  if (file->Length == 2 * wcslen(ole)) {
    printf("ok!\n");
    return file;
  } else {
    printf("no!\n");
    return 0;
  }
}


int main() {

  test1();
  return;
}

