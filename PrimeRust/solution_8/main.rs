// SPDX-License-Identifier: BSD-3-Clause
#![allow(dead_code)]
mod unrolled;
mod primes {
    pub const fn square_start(p: usize) -> usize { p*p/2 }
    pub trait FlagStorage {
        const ALGORITHM: &'static str;
        fn create_true(size: usize) -> Self;
        fn reset_flags(&mut self, skip: usize);
        fn get(&self, index: usize) -> bool;
        fn run_sieve(&mut self, limit: usize);
    }
}
use primes::FlagStorage;
use unrolled::FlagStorageUnrolledHybrid as Storage;
use std::time::Instant;
struct Sieve { limit: usize, storage: Storage }
impl Sieve {
    fn new(limit: usize) -> Self { Self { limit, storage: Storage::create_true(limit/2+1) } }
    fn run(&mut self) { self.storage.run_sieve(self.limit); }
    fn prime(&self,n:usize) -> bool { n>=2 && n<=self.limit && (n==2 || (n%2==1 && self.storage.get(n/2))) }
    fn count(&self) -> usize { (2..=self.limit).filter(|&n|self.prime(n)).count() }
}
fn main() {
    let seconds=std::env::args().nth(1).map(|s|s.parse::<f64>().expect("seconds")).unwrap_or(5.0);
    assert!(seconds>=5.0 && seconds.is_finite());
    let start=Instant::now(); let mut passes=0;
    let elapsed=loop {
        let mut s=Sieve::new(1_000_000); s.run();
        std::hint::black_box(&s);
        passes+=1;
        let elapsed=start.elapsed().as_secs_f64();
        if elapsed>=seconds { assert_eq!(s.count(),78_498); break elapsed; }
    };
    let author=include_str!("author.txt").trim();
    println!("{author}-rust-{};{passes};{elapsed:.9};1;algorithm={},faithful=yes,bits=1",Storage::ALGORITHM,Storage::ALGORITHM);
    eprintln!("Valid: Pass; primes: 78498");
}
#[cfg(test)] mod tests {
    use super::*;
    #[test] fn independent_full_flags_and_counts() {
        for n in [0,1,2,3,9,25,49,127,128,129,169,1048575,1048576,1048577,2000003] {
            let mut oracle=vec![true;n+1]; oracle[0]=false; if n>0 {oracle[1]=false;}
            for p in 2..=n { if p>n/p {break} if oracle[p] {for m in (p*p..=n).step_by(p) {oracle[m]=false}} }
            let mut s=Sieve::new(n); s.run();
            for (i,&flag) in oracle.iter().enumerate() {assert_eq!(s.prime(i),flag,"limit {n}, number {i}");}
            assert_eq!(s.count(),oracle.iter().filter(|&&f|f).count());
        }
        let mut s=Sieve::new(10_000_000);s.run();assert_eq!(s.count(),664579);
    }
}
