// SPDX-License-Identifier: BSD-3-Clause
// Dense/sparse unrolling follows Mike Barber and GordonBGood (PrimeRust/solution_1).
// Runtime stride decomposition follows PrimeLisp/solution_3.
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <assert.h>
#if __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error "This byte/word hybrid requires little-endian storage."
#endif

#ifndef WORDS_PER_BLOCK
#define WORDS_PER_BLOCK 4096
#endif
#ifndef CATEGORY
#define CATEGORY "wheel"
#endif

struct sieve { size_t limit, count; uint64_t *words; };
static struct sieve create_sieve(size_t limit) {
    size_t count = ((limit + 1) / 2 + 63) / 64;
    uint64_t *words = calloc(count ? count : 1, sizeof *words);
    if (!words) { perror("calloc"); exit(1); }
    words[0] = 1;
    return (struct sieve){limit, count, words};
}
static int prime_at(const struct sieve *s, size_t n) {
    return n >= 2 && n <= s->limit &&
        (n == 2 || ((n & 1) && !(s->words[n / 128] & (UINT64_C(1) << ((n / 2) % 64)))));
}

#define EIGHT(F,P,K) F(P,(K)); F(P,(K)+1); F(P,(K)+2); F(P,(K)+3); \
                     F(P,(K)+4); F(P,(K)+5); F(P,(K)+6); F(P,(K)+7)
#define SIXTY_FOUR(F,P) EIGHT(F,P,0); EIGHT(F,P,8); EIGHT(F,P,16); EIGHT(F,P,24); \
                        EIGHT(F,P,32); EIGHT(F,P,40); EIGHT(F,P,48); EIGHT(F,P,56)
#define ODD_EIGHT(F,K) F((K)+1) F((K)+3) F((K)+5) F((K)+7) F((K)+9) F((K)+11) F((K)+13) F((K)+15)
#define DENSE_FACTORS(F) ODD_EIGHT(F,2) ODD_EIGHT(F,18) ODD_EIGHT(F,34) ODD_EIGHT(F,50) \
                         ODD_EIGHT(F,66) ODD_EIGHT(F,82) ODD_EIGHT(F,98) ODD_EIGHT(F,114)
// Each operation sets exactly one bit. The compiler may fold/vectorize these ORs.
#define DENSE_BIT(P,K) ptr[((P)/2+(K)*(P))/64] |= UINT64_C(1) << (((P)/2+(K)*(P))%64)
#define DENSE_CASE(P) case P: { \
    size_t first = (P)/128; size_t i = (first > begin/(P) ? first : begin/(P))*(P); \
    for (; i+(P)<=end; i+=(P)) { uint64_t *ptr=s->words+i; SIXTY_FOUR(DENSE_BIT,P); } \
    for (size_t k=0;k<64;k++) { size_t bit=(P)/2+k*(P); \
        if (i+bit/64 >= end) { break; } s->words[i+bit/64] |= UINT64_C(1)<<(bit%64); } \
    s->words[(P)/128] &= ~(UINT64_C(1)<<(((P)/2)%64)); break; }
static __attribute__((noinline)) void mark_dense(struct sieve *s, size_t p, size_t begin, size_t end) {
    switch (p) { DENSE_FACTORS(DENSE_CASE) }
}

// Cofactors coprime to 30: a 240-cofactor period has 64 writes.
#define WHEEL_BIT(R,M) do { if ((M)%3 && (M)%5) \
    bytes[i+(M)*q+(M)*(R)/16] |= 1u<<(((M)*(R)/2)%8); } while(0)
#define WHEEL_FOUR(R,G) WHEEL_BIT(R,(G)*8+1); WHEEL_BIT(R,(G)*8+3); \
                       WHEEL_BIT(R,(G)*8+5); WHEEL_BIT(R,(G)*8+7)
#define WHEEL_PERIOD(R) EIGHT(WHEEL_FOUR,R,0); EIGHT(WHEEL_FOUR,R,8); \
                       EIGHT(WHEEL_FOUR,R,16); \
                       WHEEL_FOUR(R,24); WHEEL_FOUR(R,25); WHEEL_FOUR(R,26); \
                       WHEEL_FOUR(R,27); WHEEL_FOUR(R,28); WHEEL_FOUR(R,29)
#define WHEEL_CASE(R) case R: { \
    for (; i+period<=end; i+=period) { WHEEL_PERIOD(R); } \
    for(size_t m=1;m<240;m+=2) if(m%3 && m%5) { size_t j=i+m*q+m*(R)/16; \
        if(j>=end) { break; } bytes[j] |= 1u<<(((m*(R))/2)%8); } break; }
static __attribute__((noinline)) void mark_sparse(struct sieve *s, size_t p, size_t begin, size_t end) {
    uint8_t *bytes=(uint8_t*)s->words;
    begin*=8; end*=8;
    size_t q=p/16,period=15*p;
    size_t start=(p/240 > begin/period ? p/240 : begin/period)*period;
    size_t i=start;
    switch(p%16) { ODD_EIGHT(WHEEL_CASE,0) }
    if(!start) bytes[p/16] &= ~(1u<<((p/2)%8));
}
static __attribute__((noinline)) void run_sieve(struct sieve *s) {
    for(size_t begin=0;begin<s->count;begin+=WORDS_PER_BLOCK) {
        size_t end=begin+WORDS_PER_BLOCK;
        if(end>s->count) end=s->count;
        size_t limit=end*128 < s->limit ? end*128 : s->limit;
        for(size_t p=3;p<=limit/p;p+=2) {
            if(!prime_at(s,p)) continue;
            if(p<=129) mark_dense(s,p,begin,end);
            else mark_sparse(s,p,begin,end);
        }
    }
}
static size_t count_primes(const struct sieve *s) {
    size_t count=0;
    for(size_t n=2;n<=s->limit;n++) count += prime_at(s,n);
    return count;
}
static void check_one(size_t limit) {
    unsigned char *oracle=calloc(limit+1,1);
    assert(oracle);
    for(size_t p=2;p<=limit/p;p++) if(!oracle[p])
        for(size_t n=p*p;n<=limit;n+=p) oracle[n]=1;
    struct sieve s=create_sieve(limit); run_sieve(&s);
    for(size_t n=0;n<=limit;n++) if(prime_at(&s,n) != (n>=2 && !oracle[n])) {
        fprintf(stderr,"Mismatch: limit=%zu, n=%zu\n",limit,n); exit(1);
    }
    free(s.words); free(oracle);
}
static void check(void) {
    for(size_t n=0;n<300;n++) check_one(n);
    const size_t boundaries[]={1024,131*131,239*239,241*241,262144,524288,1000000,2000003};
    for(size_t k=0;k<sizeof boundaries/sizeof *boundaries;k++)
        for(int delta=-2;delta<=2;delta++) check_one(boundaries[k]+delta);
    struct sieve s=create_sieve(10000000); run_sieve(&s);
    assert(count_primes(&s)==664579); free(s.words);
    fputs("All flags and 10M count verified.\n",stderr);
}
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec*1e-9; }
int main(int argc,char **argv) {
    if(argc>1 && !strcmp(argv[1],"check")) { check(); return 0; }
    double seconds=argc>1 ? strtod(argv[1],NULL) : 5;
    if(seconds<5) { fputs("Use at least five seconds.\n",stderr); return 2; }
    size_t passes=0; double start=now(), finish;
    for(;;) {
        struct sieve s=create_sieve(1000000); run_sieve(&s); passes++; finish=now();
        if(finish-start>=seconds) {
            size_t count=count_primes(&s); free(s.words);
            if(count!=78498) { fprintf(stderr,"Invalid count: %zu\n",count); return 1; } break;
        }
        free(s.words);
    }
    char author[128];
    FILE *attribution = fopen("author.txt", "r");
    if (!attribution || !fgets(author, sizeof author, attribution)) {
        fputs("Cannot read author.txt\n", stderr); return 1;
    }
    fclose(attribution);
    author[strcspn(author, "\r\n")] = 0;
    printf("%s-c-%s;%zu;%.9f;1;algorithm=%s,faithful=yes,bits=1\n",author,CATEGORY,passes,finish-start,CATEGORY);
    fputs("Valid: Pass; primes: 78498\n",stderr);
    return 0;
}
