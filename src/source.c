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

static void crepl_assert(const char *msg, int ok) {{
  if (ok)
    return;
  perror(msg);
  exit(1);
}}

static int crepl_stdout = 1;
static int crepl_stderr = 2;

static void crepl_supress_output(void) {{
  crepl_stdout = dup(1);
  crepl_stderr = dup(2);
  int nullfd = open("/dev/null", O_WRONLY);
  crepl_assert("open", nullfd != -1);
  crepl_assert("dup2", dup2(nullfd, 1) != -1);
  crepl_assert("dup2", dup2(nullfd, 2) != -1);
  crepl_assert("close", close(nullfd) != -1);
}}

static void crepl_resume_output(void) {{
  crepl_assert("fflush", fflush(stdout) == 0);
  crepl_assert("fflush", fflush(stderr) == 0);
  crepl_assert("dup2", dup2(crepl_stdout, 1) != -1);
  crepl_assert("dup2", dup2(crepl_stderr, 2) != -1);
  crepl_assert("close", close(crepl_stdout) != -1);
  crepl_assert("close", close(crepl_stderr) != -1);
}}

{[includes]s}

int main(void) {{
  crepl_supress_output();
  {[exprs]s}
  crepl_resume_output();
  {[expr]s}
}}
