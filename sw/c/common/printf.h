///////////////////////////////////////////////////////////////////////////////
// Tiny printf interface used for bare-metal software.
// Based on the MIT-licensed implementation by Marco Paland.
///////////////////////////////////////////////////////////////////////////////

#ifndef COREJACK_PRINTF_H_
#define COREJACK_PRINTF_H_

#include <stdarg.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void _putchar(char character);

#define printf printf_
int printf_(const char *format, ...);

#define sprintf sprintf_
int sprintf_(char *buffer, const char *format, ...);

#define snprintf snprintf_
#define vsnprintf vsnprintf_
int snprintf_(char *buffer, size_t count, const char *format, ...);
int vsnprintf_(char *buffer, size_t count, const char *format, va_list va);

int fctprintf(void (*out)(char character, void *arg), void *arg,
              const char *format, ...);

#ifdef __cplusplus
}
#endif

#endif
