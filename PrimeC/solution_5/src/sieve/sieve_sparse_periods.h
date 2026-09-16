// SPDX-License-Identifier: BSD-3-Clause
// Eight individual byte writes per period. The runtime stride and constant
// carries follow the Lisp native-storage kernel and Rust solution_1.
// The bounded overlap writes only composites; the factor lies before p*p.
#define SPARSE_EIGHT(F,R) F(R,0); F(R,1); F(R,2); F(R,3); F(R,4); F(R,5); F(R,6); F(R,7)
#define SPARSE_BIT(R,K) bytes[i + q + (K)*step + ((R)/2+(K)*((R)%8))/8] |= 1u << (((R)/2+(K)*(R))%8)
#define SPARSE_CASE(R) case R: { \
    for (;i+p<=end;i+=p) { SPARSE_EIGHT(SPARSE_BIT,R); } \
    for (size_t k=0;k<8;k++) { size_t j=i+q+k*step+((R)/2+k*((R)%8))/8; \
        if(j>=end) break; bytes[j] |= 1u<<(((R)/2+k*(R))%8); } break; }
static __attribute__((noinline)) void markSparsePeriods(void *storage, size_t p, size_t begin, size_t end) {
    uint8_t *bytes=(uint8_t*)storage;
    begin /= 8; end = (end + 8) / 8;
    size_t q=p/16, step=p/8;
    size_t i=(q > begin/p ? q : begin/p)*p;
    switch(p%16) { SPARSE_CASE(1) SPARSE_CASE(3) SPARSE_CASE(5) SPARSE_CASE(7) SPARSE_CASE(9) SPARSE_CASE(11) SPARSE_CASE(13) SPARSE_CASE(15) }
}


#undef SPARSE_EIGHT
#undef SPARSE_BIT
#undef SPARSE_CASE
