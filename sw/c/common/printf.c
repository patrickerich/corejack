///////////////////////////////////////////////////////////////////////////////
// Tiny printf implementation.
// Based on the MIT-licensed implementation by Marco Paland.
///////////////////////////////////////////////////////////////////////////////

#include <stdbool.h>
#include <stdint.h>

#include "printf.h"

#ifndef PRINTF_NTOA_BUFFER_SIZE
#define PRINTF_NTOA_BUFFER_SIZE 32U
#endif

#ifndef PRINTF_DISABLE_SUPPORT_LONG_LONG
#define PRINTF_SUPPORT_LONG_LONG
#endif

#define FLAGS_ZEROPAD   (1U << 0U)
#define FLAGS_LEFT      (1U << 1U)
#define FLAGS_PLUS      (1U << 2U)
#define FLAGS_SPACE     (1U << 3U)
#define FLAGS_HASH      (1U << 4U)
#define FLAGS_UPPERCASE (1U << 5U)
#define FLAGS_CHAR      (1U << 6U)
#define FLAGS_SHORT     (1U << 7U)
#define FLAGS_LONG      (1U << 8U)
#define FLAGS_LONG_LONG (1U << 9U)
#define FLAGS_PRECISION (1U << 10U)

typedef void (*out_fct_type)(char character, void *buffer, size_t idx,
                             size_t maxlen);

typedef struct {
  void (*fct)(char character, void *arg);
  void *arg;
} out_fct_wrap_type;

static inline void _out_buffer(char character, void *buffer, size_t idx,
                               size_t maxlen) {
  if (idx < maxlen) {
    ((char *)buffer)[idx] = character;
  }
}

static inline void _out_null(char character, void *buffer, size_t idx,
                             size_t maxlen) {
  (void)character;
  (void)buffer;
  (void)idx;
  (void)maxlen;
}

static inline void _out_char(char character, void *buffer, size_t idx,
                             size_t maxlen) {
  (void)buffer;
  (void)idx;
  (void)maxlen;
  if (character != '\0') {
    _putchar(character);
  }
}

static inline void _out_fct(char character, void *buffer, size_t idx,
                            size_t maxlen) {
  (void)idx;
  (void)maxlen;
  if (character != '\0') {
    ((out_fct_wrap_type *)buffer)
        ->fct(character, ((out_fct_wrap_type *)buffer)->arg);
  }
}

static inline unsigned int _strnlen_s(const char *str, size_t maxsize) {
  const char *s;
  for (s = str; *s != '\0' && maxsize--; ++s) {
  }
  return (unsigned int)(s - str);
}

static inline bool _is_digit(char ch) {
  return (ch >= '0') && (ch <= '9');
}

static unsigned int _atoi(const char **str) {
  unsigned int i = 0U;
  while (_is_digit(**str)) {
    i = i * 10U + (unsigned int)(*((*str)++) - '0');
  }
  return i;
}

static size_t _out_rev(out_fct_type out, char *buffer, size_t idx,
                       size_t maxlen, const char *buf, size_t len,
                       unsigned int width, unsigned int flags) {
  const size_t start_idx = idx;

  if ((flags & FLAGS_LEFT) == 0U) {
    while (len < width) {
      out((flags & FLAGS_ZEROPAD) != 0U ? '0' : ' ', buffer, idx++, maxlen);
      width--;
    }
  }

  while (len > 0U) {
    out(buf[--len], buffer, idx++, maxlen);
  }

  if ((flags & FLAGS_LEFT) != 0U) {
    while ((idx - start_idx) < width) {
      out(' ', buffer, idx++, maxlen);
    }
  }

  return idx;
}

static size_t _ntoa_format(out_fct_type out, char *buffer, size_t idx,
                           size_t maxlen, char *buf, size_t len, bool negative,
                           unsigned int base, unsigned int prec,
                           unsigned int width, unsigned int flags) {
  if ((flags & FLAGS_LEFT) == 0U) {
    if (width != 0U && (flags & FLAGS_ZEROPAD) != 0U &&
        (negative || ((flags & (FLAGS_PLUS | FLAGS_SPACE)) != 0U))) {
      width--;
    }
    while ((len < prec) && (len < PRINTF_NTOA_BUFFER_SIZE)) {
      buf[len++] = '0';
    }
  }

  if ((flags & FLAGS_HASH) != 0U) {
    if ((base == 16U) && (len < PRINTF_NTOA_BUFFER_SIZE)) {
      buf[len++] = ((flags & FLAGS_UPPERCASE) != 0U) ? 'X' : 'x';
      buf[len++] = '0';
    }
  }

  if (negative) {
    buf[len++] = '-';
  } else if ((flags & FLAGS_PLUS) != 0U) {
    buf[len++] = '+';
  } else if ((flags & FLAGS_SPACE) != 0U) {
    buf[len++] = ' ';
  }

  return _out_rev(out, buffer, idx, maxlen, buf, len, width, flags);
}

static size_t _ntoa_long(out_fct_type out, char *buffer, size_t idx,
                         size_t maxlen, unsigned long value, bool negative,
                         unsigned long base, unsigned int prec,
                         unsigned int width, unsigned int flags) {
  char buf[PRINTF_NTOA_BUFFER_SIZE];
  size_t len = 0U;

  if (value == 0U) {
    flags &= ~FLAGS_HASH;
  }

  if (((flags & FLAGS_PRECISION) == 0U) || value != 0U) {
    do {
      const char digit = (char)(value % base);
      buf[len++] = (char)(digit < 10 ? '0' + digit
                                     : ((flags & FLAGS_UPPERCASE) != 0U ? 'A'
                                                                        : 'a') +
                                           digit - 10);
      value /= base;
    } while ((value != 0U) && (len < PRINTF_NTOA_BUFFER_SIZE));
  }

  return _ntoa_format(out, buffer, idx, maxlen, buf, len, negative,
                      (unsigned int)base, prec, width, flags);
}

#ifdef PRINTF_SUPPORT_LONG_LONG
static size_t _ntoa_long_long(out_fct_type out, char *buffer, size_t idx,
                              size_t maxlen, unsigned long long value,
                              bool negative, unsigned long long base,
                              unsigned int prec, unsigned int width,
                              unsigned int flags) {
  char buf[PRINTF_NTOA_BUFFER_SIZE];
  size_t len = 0U;

  if (value == 0U) {
    flags &= ~FLAGS_HASH;
  }

  if (((flags & FLAGS_PRECISION) == 0U) || value != 0U) {
    do {
      const char digit = (char)(value % base);
      buf[len++] = (char)(digit < 10 ? '0' + digit
                                     : ((flags & FLAGS_UPPERCASE) != 0U ? 'A'
                                                                        : 'a') +
                                           digit - 10);
      value /= base;
    } while ((value != 0U) && (len < PRINTF_NTOA_BUFFER_SIZE));
  }

  return _ntoa_format(out, buffer, idx, maxlen, buf, len, negative,
                      (unsigned int)base, prec, width, flags);
}
#endif

static int _vsnprintf(out_fct_type out, char *buffer, const size_t maxlen,
                      const char *format, va_list va) {
  unsigned int flags, width, precision, n;
  size_t idx = 0U;

  if (format == NULL) {
    return 0;
  }

  while (*format != '\0') {
    if (*format != '%') {
      out(*format, buffer, idx++, maxlen);
      format++;
      continue;
    }

    format++;
    flags = 0U;
    width = 0U;
    precision = 0U;

    do {
      switch (*format) {
        case '0': flags |= FLAGS_ZEROPAD; format++; n = 1U; break;
        case '-': flags |= FLAGS_LEFT; format++; n = 1U; break;
        case '+': flags |= FLAGS_PLUS; format++; n = 1U; break;
        case ' ': flags |= FLAGS_SPACE; format++; n = 1U; break;
        case '#': flags |= FLAGS_HASH; format++; n = 1U; break;
        default: n = 0U; break;
      }
    } while (n != 0U);

    if (_is_digit(*format)) {
      width = _atoi(&format);
    } else if (*format == '*') {
      const int w = va_arg(va, int);
      if (w < 0) {
        flags |= FLAGS_LEFT;
        width = (unsigned int)(-w);
      } else {
        width = (unsigned int)w;
      }
      format++;
    }

    if (*format == '.') {
      flags |= FLAGS_PRECISION;
      format++;
      if (_is_digit(*format)) {
        precision = _atoi(&format);
      } else if (*format == '*') {
        const int prec = va_arg(va, int);
        precision = prec > 0 ? (unsigned int)prec : 0U;
        format++;
      }
    }

    switch (*format) {
      case 'l':
        flags |= FLAGS_LONG;
        format++;
        if (*format == 'l') {
          flags |= FLAGS_LONG_LONG;
          format++;
        }
        break;
      case 'h':
        flags |= FLAGS_SHORT;
        format++;
        if (*format == 'h') {
          flags |= FLAGS_CHAR;
          format++;
        }
        break;
      default:
        break;
    }

    switch (*format) {
      case 'd':
      case 'i': {
        if ((flags & FLAGS_LONG_LONG) != 0U) {
#ifdef PRINTF_SUPPORT_LONG_LONG
          long long value = va_arg(va, long long);
          idx = _ntoa_long_long(out, buffer, idx, maxlen,
                                (unsigned long long)(value > 0 ? value : -value),
                                value < 0, 10U, precision, width, flags);
#else
          idx = _ntoa_long(out, buffer, idx, maxlen,
                           (unsigned long)va_arg(va, long long),
                           false, 10U, precision, width, flags & ~FLAGS_LONG_LONG);
#endif
        } else if ((flags & FLAGS_LONG) != 0U) {
          long value = va_arg(va, long);
          idx = _ntoa_long(out, buffer, idx, maxlen,
                           (unsigned long)(value > 0 ? value : -value),
                           value < 0, 10U, precision, width, flags);
        } else {
          int value = ((flags & FLAGS_CHAR) != 0U)
                          ? (signed char)va_arg(va, int)
                          : ((flags & FLAGS_SHORT) != 0U)
                                ? (short int)va_arg(va, int)
                                : va_arg(va, int);
          idx = _ntoa_long(out, buffer, idx, maxlen,
                           (unsigned int)(value > 0 ? value : -value),
                           value < 0, 10U, precision, width, flags);
        }
        format++;
        break;
      }
      case 'u':
      case 'x':
      case 'X': {
        const unsigned int base = (*format == 'u') ? 10U : 16U;
        if (*format == 'X') {
          flags |= FLAGS_UPPERCASE;
        }
        if ((flags & FLAGS_LONG_LONG) != 0U) {
#ifdef PRINTF_SUPPORT_LONG_LONG
          idx = _ntoa_long_long(out, buffer, idx, maxlen,
                                va_arg(va, unsigned long long), false, base,
                                precision, width, flags);
#else
          idx = _ntoa_long(out, buffer, idx, maxlen,
                           (unsigned long)va_arg(va, unsigned long long), false,
                           base, precision, width, flags & ~FLAGS_LONG_LONG);
#endif
        } else if ((flags & FLAGS_LONG) != 0U) {
          idx = _ntoa_long(out, buffer, idx, maxlen,
                           va_arg(va, unsigned long), false, base,
                           precision, width, flags);
        } else {
          idx = _ntoa_long(out, buffer, idx, maxlen,
                           (flags & FLAGS_CHAR) != 0U
                               ? (unsigned char)va_arg(va, unsigned int)
                               : (flags & FLAGS_SHORT) != 0U
                                     ? (unsigned short int)va_arg(va, unsigned int)
                                     : va_arg(va, unsigned int),
                           false, base, precision, width, flags);
        }
        format++;
        break;
      }
      case 'c': {
        unsigned int l = 1U;
        if ((flags & FLAGS_LEFT) == 0U) {
          while (l++ < width) {
            out(' ', buffer, idx++, maxlen);
          }
        }
        out((char)va_arg(va, int), buffer, idx++, maxlen);
        if ((flags & FLAGS_LEFT) != 0U) {
          while (l++ < width) {
            out(' ', buffer, idx++, maxlen);
          }
        }
        format++;
        break;
      }
      case 's': {
        const char *p = va_arg(va, char *);
        unsigned int l = _strnlen_s(p, precision != 0U ? precision : (size_t)-1);
        if ((flags & FLAGS_LEFT) == 0U) {
          while (l < width) {
            out(' ', buffer, idx++, maxlen);
            width--;
          }
        }
        while ((*p != '\0') && ((flags & FLAGS_PRECISION) == 0U || l-- != 0U)) {
          out(*p++, buffer, idx++, maxlen);
        }
        if ((flags & FLAGS_LEFT) != 0U) {
          while (l < width) {
            out(' ', buffer, idx++, maxlen);
            width--;
          }
        }
        format++;
        break;
      }
      case 'p': {
        width = sizeof(void *) * 2U;
        flags |= FLAGS_ZEROPAD | FLAGS_UPPERCASE;
#ifdef PRINTF_SUPPORT_LONG_LONG
        idx = _ntoa_long_long(out, buffer, idx, maxlen,
                              (uintptr_t)va_arg(va, void *), false, 16U,
                              precision, width, flags);
#else
        idx = _ntoa_long(out, buffer, idx, maxlen,
                         (unsigned long)(uintptr_t)va_arg(va, void *), false,
                         16U, precision, width, flags);
#endif
        format++;
        break;
      }
      case '%':
        out('%', buffer, idx++, maxlen);
        format++;
        break;
      default:
        out(*format, buffer, idx++, maxlen);
        format++;
        break;
    }
  }

  out('\0', buffer, idx < maxlen ? idx : maxlen, maxlen);
  return (int)idx;
}

int printf_(const char *format, ...) {
  va_list va;
  va_start(va, format);
  const int ret = _vsnprintf(_out_char, NULL, (size_t)-1, format, va);
  va_end(va);
  return ret;
}

int sprintf_(char *buffer, const char *format, ...) {
  va_list va;
  va_start(va, format);
  const int ret = _vsnprintf(_out_buffer, buffer, (size_t)-1, format, va);
  va_end(va);
  return ret;
}

int snprintf_(char *buffer, size_t count, const char *format, ...) {
  va_list va;
  va_start(va, format);
  const int ret = _vsnprintf(_out_buffer, buffer, count, format, va);
  va_end(va);
  return ret;
}

int vsnprintf_(char *buffer, size_t count, const char *format, va_list va) {
  return _vsnprintf(_out_buffer, buffer, count, format, va);
}

int fctprintf(void (*out)(char character, void *arg), void *arg,
              const char *format, ...) {
  out_fct_wrap_type out_fct_wrap = {
      .fct = out,
      .arg = arg,
  };

  va_list va;
  va_start(va, format);
  const int ret =
      _vsnprintf(_out_fct, (char *)(uintptr_t)&out_fct_wrap, (size_t)-1,
                 format, va);
  va_end(va);
  return ret;
}
