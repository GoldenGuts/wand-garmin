// Send one file to an MTP device into the folder with the given parent id.
// Usage: mtpsend <local file> <remote name> <parent folder id>
#include <libmtp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
int main(int argc, char **argv) {
  if (argc != 4) { fprintf(stderr, "usage: %s local remote parent_id\n", argv[0]); return 2; }
  LIBMTP_Init();
  LIBMTP_raw_device_t *raw; int n;
  if (LIBMTP_Detect_Raw_Devices(&raw, &n) != LIBMTP_ERROR_NONE || n == 0) { fprintf(stderr, "no device\n"); return 1; }
  LIBMTP_mtpdevice_t *dev = LIBMTP_Open_Raw_Device_Uncached(&raw[0]);
  if (!dev) { fprintf(stderr, "open failed\n"); return 1; }
  struct stat st; if (stat(argv[1], &st) != 0) { perror("stat"); return 1; }
  LIBMTP_file_t *f = LIBMTP_new_file_t();
  f->filesize = st.st_size;
  f->filename = strdup(argv[2]);
  f->filetype = LIBMTP_FILETYPE_UNKNOWN;
  f->parent_id = (uint32_t) strtoul(argv[3], NULL, 10);
  f->storage_id = 0;
  int r = LIBMTP_Send_File_From_File(dev, argv[1], f, NULL, NULL);
  if (r != 0) { LIBMTP_Dump_Errorstack(dev); LIBMTP_Clear_Errorstack(dev); }
  else printf("sent %s as %s (id %u) into folder %u\n", argv[1], f->filename, f->item_id, f->parent_id);
  LIBMTP_destroy_file_t(f);
  LIBMTP_Release_Device(dev);
  free(raw);
  return r;
}
