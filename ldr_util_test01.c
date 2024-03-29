
#include <windows.h>
#include <winternl.h>
#include <wchar.h>
#include <ntstatus.h>

#include <stdio.h>
#include <stdint.h>

extern void* _get_ntdll_faddr_1(void*);
extern void* _enumerate_export_table_2(int,void*);
extern void* _enumerate_import_table_2(int,void*);

// return not module base but ldr_table_entry
extern void* _get_ldr_data_table_entry_1(int);
extern void* _enumerate_ldr_data_table_entry_1(void*);


void __f1(uint8_t* b) {
  // heads address of ldr_data_table_entry is coming.
  // +0x50 is the buffer of unicode string of this dll.
  wprintf(L"f1:dll name : %s\n",*(uint64_t*)(b + 0x50));
}

void __f2(uint8_t* p,uint8_t* f) {
  
  if (*p == 'N' && *(p+1) == 't') {
    //printf("NT!\n");
    if (*(f+3) == 0xb8) {
      printf("NT\n");
      printf("f2:function name:%s\nfunction address : %p\nsyscall num:%d\n",p,f,*(uint32_t*)(f+4));
    } else {
      printf("f2:function name:%s\nfunction address : %p\n",p,f);
    }
    printf("--------------------------------------------------------------\n");
  }
}

// callback function for import directory enumeration.
// 1st :: head of import directory entry
// 2nd :: 
void __f3(uint8_t* m,uint8_t* d,uint8_t* p,uint8_t* f) {

  printf("f3,DLL name : %s\n",d);
  printf("function name ; %s \naddress : %p\n",p,f);
  
  if (p == f) {
    printf("error\n");
  }
  printf("--------------------------------------------------------------\n");

}

int main() {
  
  uint8_t* v = _get_ntdll_faddr_1("LdrLoadDll");
  printf("%p\n",v);

  _enumerate_ldr_data_table_entry_1(&__f1);
  
  // first arg is index in load order module.
  // 1 means 2nd loaded module (ntdll).
  v = _enumerate_export_table_2(1,&__f2);

  // first arg is index in load order module.
  // 2 means 3rd loaded module (kernel32).
  v = _enumerate_import_table_2(2,&__f3);
  
}


