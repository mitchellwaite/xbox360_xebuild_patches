#ifndef FS1888_H
#define FS1888_H
#include "../bb.h"

extern u8 *dx;

void fs_init(void);
s32 fs_mount(void);
s32 fs_begin(void);
s32 fs_end(void);
s32 fs_write_file(const char *name, const u8 *data, u32 len);
s32 fs_delete_file(const char *name);
s32 fs_load_root(void);
int fs_list(char names[][23], u32 *sizes, int max);
s32 fs_read_file(const char *name, u8 *out, u32 *len);
s32 fs_mobile_write(u32 k, const u8 *data, u32 size);
s32 fs_mobile_read(u32 k, u8 *out, u32 *size);
u8 *fs_open_ro(const char *name);
s32 fs_entry_start(const char *name);

#endif
