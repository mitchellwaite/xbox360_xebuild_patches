#ifndef NANDSIM_H
#define NANDSIM_H
#include <setjmp.h>
#include <stddef.h>
#include "../bb.h"

extern u8 *nand;
extern long sim_ops, sim_cut_at, sim_violations, sim_erases, sim_programs;
extern u32 sim_invalidations;
extern jmp_buf sim_cut_jmp;

void *mmap32(size_t n);
void ecc_encode(const u8 *data, u8 *spare);
void sim_load(const char *path);
void sim_reset_state(void);
void sim_save(const char *path);
void sim_fail_erase(u32 blk);
void sim_fail_program(u32 blk);
void *sim_snapshot(void);
void sim_restore(void *s);
void sim_snap_free(void *s);

#endif
