#define _GNU_SOURCE
#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <fcntl.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#if __STDC_VERSION__ >= 199409L
  #include <iso646.h>
  #include <wchar.h>
  #include <wctype.h>
#endif
#if __STDC_VERSION__ >= 199901L
  #include <complex.h>
  #include <fenv.h>
  #include <inttypes.h>
  #include <stdbool.h>
  #include <stdint.h>
  #include <tgmath.h>
#endif
#if __STDC_VERSION__ >= 201112L
  #include <stdalign.h>
  #include <stdatomic.h>
  #include <stdnoreturn.h>
  #include <threads.h>
  #include <uchar.h>
#endif
#if __STDC_VERSION >= 202300L
  #include <stdbit.h>
  #include <stdckdint.h>
#endif

static void crepl_assert(int ok, const char *msg) {{
  if (ok)
    return;
  perror(msg);
  exit(1);
}}

static int crepl_supress(FILE *f, int fd) {{
  int ret = dup(fd);
  int nullfd = open("/dev/null", O_WRONLY);
  crepl_assert(nullfd != -1, "open");
  crepl_assert(dup2(nullfd, 1) != -1, "dup2");
  crepl_assert(close(nullfd) != -1, "close");
  return ret;
}}

static void crepl_resume(FILE *f, int saved_fd, int fd) {{
  crepl_assert(fflush(f) == 0, "fflush");
  crepl_assert(dup2(saved_fd, fd) != -1, "dup2");
  crepl_assert(close(saved_fd) != -1, "close");
}}

{[includes]s}

int main(void) {{
  int stdout_fd = crepl_supress(stdout, 1);
  int stderr_fd = crepl_supress(stderr, 2);

  {[exprs]s}

  crepl_resume(stdout, stdout_fd, 1);
  crepl_resume(stderr, stderr_fd, 2);

  {[expr]s}
}}
