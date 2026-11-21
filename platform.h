#ifndef PIANO_PLATFORM_H
#define PIANO_PLATFORM_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
typedef int32_t LONG;
#define MAX_PATH 4096
static int DeleteFileA(const char *path) { return remove(path)==0; }
#endif
#ifndef PI
#define PI 3.14159265358979323846
#endif
#ifndef RATE
#define RATE 44100
#endif
#endif
