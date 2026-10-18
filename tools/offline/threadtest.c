/* SPDX-License-Identifier: LGPL-2.1-or-later
 * Enroll on one thread, verify on another after re-opening the engine, the
 * way fprintd runs libfprint operations on GTask worker threads.
 *
 * usage: threadtest DLL frames.bmp...
 */
#include "vendor-engine.h"
#include "bmp.h"
#include <pthread.h>

static int ac;
static char **av;
static uint8_t *tmpl;
static size_t tmpl_len;

static void *enroll_thread(void *x)
{
  ft_engine_enroll_begin();
  for (int i = 2; i < ac; i++) {
    uint8_t *img = 0; int sw, sh;
    if (bmp(av[i], &img, &sw, &sh)) continue;
    int done = ft_engine_accept(img, sw, sh, 4) == 0 && ft_engine_enroll_update() == 0;
    free(img);
    if (done) break;
  }
  printf("commit=%d template=%zu\n", ft_engine_enroll_commit(&tmpl, &tmpl_len), tmpl_len);
  return 0;
}

static void *verify_thread(void *x)
{
  printf("reopen=%d\n", ft_engine_open(av[1]));
  int m = 0, t = 0;
  for (int i = 2; i < ac; i++) {
    uint8_t *img = 0; int sw, sh;
    if (bmp(av[i], &img, &sw, &sh)) continue;
    if (ft_engine_accept(img, sw, sh, 1) == 0) { t++; m += ft_engine_verify(tmpl, tmpl_len); }
    free(img);
  }
  printf("verify: %d/%d matched\n", m, t);
  return 0;
}

int main(int c, char **v)
{
  if (c < 3) { fprintf(stderr, "usage: %s DLL frames.bmp...\n", v[0]); return 2; }
  ac = c; av = v;
  printf("open=%d\n", ft_engine_open(v[1]));
  pthread_t a, b;
  pthread_create(&a, 0, enroll_thread, 0); pthread_join(a, 0);
  pthread_create(&b, 0, verify_thread, 0); pthread_join(b, 0);
  return 0;
}
