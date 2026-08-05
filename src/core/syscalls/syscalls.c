/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * This file is part of RFX Firmware.
 *
 * Copyright (C) 2026 Rotorflight Project.
 *
 * RFX Firmware is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * RFX Firmware is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <https://www.gnu.org/licenses/>.
 */

/*
 * The syscall stubs newlib links against. There is no operating system
 * underneath and the firmware opens no files, so each one fails.
 *
 * Defined here so the toolchain's own are never linked: libnosys supplies the
 * same failures, four of them carrying a .gnu.warning section the linker
 * prints on every build.
 *
 * None of these set errno. Doing so would pull in newlib's reentrancy
 * structures — _impure_data and a 312-byte stdio FILE table among them — and
 * nothing in the image reads errno back.
 */

#include <stddef.h>

#include <sys/stat.h>
#include <sys/types.h>

#include "core/common/core.h"

/*
 * -Wmissing-prototypes requires a declaration ahead of every definition. There
 * is no header to take these from: newlib declares the underscore names only
 * under #ifdef _LIBC, while the library itself is being built.
 */
int _close(int fd);
int _fstat(int fd, struct stat *st);
int _getpid(void);
int _isatty(int fd);
int _kill(int pid, int sig);
off_t _lseek(int fd, off_t offset, int whence);
ssize_t _read(int fd, void *buf, size_t count);
void *_sbrk(ptrdiff_t increment);
ssize_t _write(int fd, const void *buf, size_t count);

_Noreturn void _exit(int status);

int _close(int fd)
{
    UNUSED(fd);
    return -1;
}

int _fstat(int fd, struct stat *st)
{
    UNUSED(fd);
    UNUSED(st);
    return -1;
}

int _getpid(void)
{
    return -1;
}

int _isatty(int fd)
{
    UNUSED(fd);
    return 0;
}

int _kill(int pid, int sig)
{
    UNUSED(pid);
    UNUSED(sig);
    return -1;
}

off_t _lseek(int fd, off_t offset, int whence)
{
    UNUSED(fd);
    UNUSED(offset);
    UNUSED(whence);
    return -1;
}

ssize_t _read(int fd, void *buf, size_t count)
{
    UNUSED(fd);
    UNUSED(buf);
    UNUSED(count);
    return -1;
}

/* There is no heap. Nothing allocates after init, so the break never moves. */
void *_sbrk(ptrdiff_t increment)
{
    UNUSED(increment);
    return (void *)-1;
}

/* TODO: route to the debug console once one exists. */
ssize_t _write(int fd, const void *buf, size_t count)
{
    UNUSED(fd);
    UNUSED(buf);
    UNUSED(count);
    return -1;
}

/* Halt. There is nothing to return to */
_Noreturn void _exit(int status)
{
    UNUSED(status);
    FOREVER;
}
