#define main submission_main
#include "src/sieve_extend.c"
#undef main
int main(void) {
 setDefaultOptions();
 const size_t limits[]={1000,10000,100000,262144,524288,999999,1000000,1000001,2000003,10000000};
 for(size_t algorithm=1;algorithm<=2;algorithm++) for(size_t b=131072;b<=524288;b*=2) for(size_t k=0;k<sizeof limits/sizeof *limits;k++) {
  size_t n=limits[k];
  unsigned char *oracle=calloc(n+1,1);
  for(size_t p=2;p<=n/p;p++) if(!oracle[p]) for(size_t m=p*p;m<=n;m+=p) oracle[m]=1;
  benchmark_settings_t settings=initBenchmarkSettings(1);
  settings.factor_max=n;settings.blocksize_bits=b;settings.algorithm=algorithm;
  prepareBenchmarkGlobals(settings);
  struct sieve_t *s=shakeSieve(n);
  for(size_t i=3;i<n;i+=2) {
   int flag=(((uint8_t*)s->bitstorage)[i/16]>>(i/2%8))&1;
   if(flag!=oracle[i]) {fprintf(stderr,"bad n=%zu block=%zu i=%zu\n",n,b,i);return 1;}
  }
  free(oracle);sieve_delete(s);
 }
 fprintf(stderr,"C extend all flags verified, both algorithms, three block sizes, through 10M.\n");
}
