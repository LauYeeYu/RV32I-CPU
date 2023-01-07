#include "io.h"
// This testcase flushes the cache line very quickly to find bugs in DCache

int a[3000];
int main() {
  for (int i = 0; i < 2500; i+= 4) {
    a[i] = i;
  }
  outlln(a[0]);
  outlln(a[2048]);
}
