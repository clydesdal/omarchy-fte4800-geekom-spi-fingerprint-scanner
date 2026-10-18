/* SPDX-License-Identifier: LGPL-2.1-or-later
 * Offline FocalTech engine replay: enroll on the first N frames, verify each
 * of the remaining frames against the resulting template.
 *
 * usage: replay DLL N enroll1.bmp ... enrollN.bmp verify1.bmp ...
 */
#include "vendor-engine.h"
#include "bmp.h"

int main(int c, char **v)
{
  if (c < 4) { fprintf(stderr, "usage: %s DLL N frames.bmp...\n", v[0]); return 2; }
  if (ft_engine_open(v[1])) return 10;
  int ne = atoi(v[2]), acc = 0, used = 0;

  ft_engine_enroll_begin();
  for (int i = 3; i < 3 + ne && i < c; i++) {
    uint8_t *img = 0; int sw, sh;
    if (bmp(v[i], &img, &sw, &sh)) continue;
    if (ft_engine_accept(img, sw, sh, 4) == 0) {
      acc++;
      if (ft_engine_enroll_update() != 2) used++;
    }
    free(img);
  }
  uint8_t *t = 0; size_t n = 0;
  int rc = ft_engine_enroll_commit(&t, &n);
  printf("enroll: accepted %d, used %d, commit=%d\n", acc, used, rc);
  if (rc) return 20;

  int m = 0, tot = 0;
  printf("verify:");
  for (int i = 3 + ne; i < c; i++) {
    uint8_t *img = 0; int sw, sh;
    if (bmp(v[i], &img, &sw, &sh)) continue;
    if (ft_engine_accept(img, sw, sh, 1) == 0) {
      int r = ft_engine_verify(t, n);
      tot++; m += r; printf(" %d", r);
    } else
      printf(" rej");
    free(img);
  }
  printf("  => %d/%d matched\n", m, tot);
  free(t);
  return 0;
}
