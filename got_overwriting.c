
#include <stdio.h>
#include <sys/mman.h>

// This is a simple example to hook puts() defined on libc.so
// on Global offset table and covert to function f2() defined on this file.

// what this does is as follows.
// 1st, find procedure linkage table(PLT) of puts examining part of text area.
// 2nd, get the pointer of PLT and get the offset of GOT.
// 3rd, get the pointer of global offset table(GOT).
// 4th, rewrite it!
// 5th, test if the hooking is worked out.

void f1() {
  // when you call put function,
  // instruction pointer which will be jumped from them will tell you
  // where is PLT.
  puts("hei!");
};

void f2() {
  const char str[] = "world!";
  // default gcc might convert printf(string\n)
  // to puts. be careful as puts had been converted to f2 itself.
  printf("%s \n", str);
};

int main() {

  unsigned char *begin = (unsigned char *)&f1;
  unsigned char *end = (unsigned char *)&f2;
  for (; begin != end; begin++) {
    // assume call instruction is represented as
    // 0xe8 + 4byte(%rip).
    if (*begin == 0xe8) {
      // cast the pointer so you can grab 4 bytes to get offset operand.
      unsigned int *offset1 = (unsigned int *)(begin + 1);
      // calculate address of PLT e.g. in assembly asm ( "lea offset(%rip),
      // %rax" ;)
      size_t *tmp_plt_addr =
          (size_t *)((size_t)(begin + 5) + (long int)(*offset1));

      // address calculation towards negative side is a bit tricky.
      // you just need to pass the beggining 3byte of original one as previous
      // subtraction altered it,
      unsigned short *plt_addr = (((size_t)tmp_plt_addr) & 0x000000ffffff) |
                                 (size_t)(begin + 4) & 0xffffff000000;
      // below might work out alternatively.
      /* size_t* plt_addr = (size_t*) ((size_t)(begin+5)+(long int)(*ptr_) -
       * 0x100000000) ; */

      // after you come to plt, what waits you is not another call, but jump.
      // And the jump is not ordinary jump but jump to the address which was set
      // on GOT. it starts from 0xff,0xx25,4byte(%rip) first 0xff is opcode, the
      // second is determining addressing. what you need to hold is last 4 byte
      // which is offset from current %rip to GOT.

      // since the type is short one step means 2byte forwards.
      plt_addr += 1;
      // get the offset which is 4 byte.
      unsigned int *offset = (unsigned int *)plt_addr;
      // proceed another 2*2(4byte) to reach %rip.
      plt_addr += 2;
      // calculate GOT of this function.
      // it does not hold any instruction but only 8byte address.
      size_t *got_addr = (size_t *)((size_t)plt_addr + (unsigned int)*offset);

      // if there is a GNU_RELRO on program headers,
      // it might be the case that libc protected the part of data segment as
      // read only after loader relocated them. you can reask kernel the mapping
      // can be writable.
      mprotect(got_addr, 4096, PROT_WRITE);
      // finally rewrite it to whatever you like to jump.
      *got_addr = (size_t)f2;
      break;
    }
  }

  // When you call puts after got overwriting,
  // f2 will be instead called.
  // make sure you get "world!" not "hello!"
  puts("hello!");
};
