/*
 * Copyright (c) 2014 DeNA Co., Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */
#include <assert.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>

#if 0
# define DEBUG_LOG(...) fprintf(stderr, __VA_ARGS__)
#else
# define DEBUG_LOG(...)
#endif

struct st_h2o_socket_loop_kqueue_t {
    h2o_socket_loop_t super;
    int kq;
};

static int collect_status(struct st_h2o_socket_loop_kqueue_t *loop, struct kevent *changelist, int changelist_capacity)
{
    int change_index = 0;

#define SET_AND_UPDATE(filter, flags) do { \
    EV_SET(changelist + change_index++, sock->fd, filter, flags, 0, 0, sock); \
    if (change_index == changelist_capacity) { \
        int ret; \
        while ((ret = kevent(loop->kq, changelist, change_index, NULL, 0, NULL)) != 0 && errno == EINTR) \
            ; \
        if (ret == -1) \
            return -1; \
        change_index = 0; \
    } \
} while (0)

    while (loop->super._statechanged.head != NULL) {
        /* detach the top */
        h2o_socket_t *sock = loop->super._statechanged.head;
        loop->super._statechanged.head = sock->_next_statechanged;
        sock->_next_statechanged = sock;
        /* update the state */
        if ((sock->_flags & H2O_SOCKET_FLAG_IS_DISPOSED) != 0) {
            free(sock);
        } else {
            if (h2o_socket_is_reading(sock)) {
                if ((sock->_flags & H2O_SOCKET_FLAG_IS_POLLED_FOR_READ) == 0) {
                    sock->_flags |= H2O_SOCKET_FLAG_IS_POLLED_FOR_READ;
                    SET_AND_UPDATE(EVFILT_READ, EV_ADD);
                }
            } else {
                if ((sock->_flags & H2O_SOCKET_FLAG_IS_POLLED_FOR_READ) != 0) {
                    sock->_flags &= ~H2O_SOCKET_FLAG_IS_POLLED_FOR_READ;
                    SET_AND_UPDATE(EVFILT_READ, EV_DELETE);
                }
            }
            if (h2o_socket_is_writing(sock) && sock->_wreq.cnt != 0) {
                if ((sock->_flags & H2O_SOCKET_FLAG_IS_POLLED_FOR_WRITE) == 0) {
                    sock->_flags |= H2O_SOCKET_FLAG_IS_POLLED_FOR_WRITE;
                    SET_AND_UPDATE(EVFILT_WRITE, EV_ADD);
                }
            } else {
                if ((sock->_flags & H2O_SOCKET_FLAG_IS_POLLED_FOR_WRITE) != 0) {
                    sock->_flags &= ~H2O_SOCKET_FLAG_IS_POLLED_FOR_WRITE;
                    SET_AND_UPDATE(EVFILT_WRITE, EV_DELETE);
                }
            }
        }
    }
    loop->super._statechanged.tail_ref = &loop->super._statechanged.head;

    return change_index;

#undef SET_AND_UPDATE
}

static int proceed(h2o_socket_loop_t *_loop, uint64_t wake_at)
{
    struct st_h2o_socket_loop_kqueue_t *loop = (struct st_h2o_socket_loop_kqueue_t*)_loop;
    struct kevent changelist[64], events[128];
    int nchanges, nevents, i;
    struct timespec ts;

    /* collect (and update) status */
    if ((nchanges = collect_status(loop, changelist, sizeof(changelist) / sizeof(changelist[0]))) == -1)
        return -1;

    /* poll */
    do {
        uint64_t max_wait;
        update_now(&loop->super);
        max_wait = loop->super.now < wake_at ? wake_at - loop->super.now : 0;
        if (max_wait > INT32_MAX)
            max_wait = INT32_MAX;
        ts.tv_sec = max_wait / 1000;
        ts.tv_nsec = max_wait % 1000 * 1000 * 1000;
    } while ((nevents = kevent(loop->kq, changelist, nchanges, events, sizeof(events) / sizeof(events[0]), &ts)) == -1
        && errno == EINTR);
    if (nevents == -1)
        return -1;

    update_now(&loop->super);

    /* update readable flags, perform writes */
    for (i = 0; i != nevents; ++i) {
        h2o_socket_t *sock = events[i].udata;
        assert(sock->fd == events[i].ident);
        switch (events[i].filter) {
        case EVFILT_READ:
            if (sock->_flags != H2O_SOCKET_FLAG_IS_DISPOSED) {
                sock->_flags |= H2O_SOCKET_FLAG_IS_READ_READY;
                h2o_socket__link_to_pending(sock);
            }
            break;
        case EVFILT_WRITE:
            if (sock->_flags != H2O_SOCKET_FLAG_IS_DISPOSED) {
                h2o_socket__write_pending(sock);
            }
            break;
        default:
            break; /* ??? */
        }
    }

    return 0;
}

static void on_create(h2o_socket_t *sock)
{
}

static void on_close(h2o_socket_t *sock)
{
}

h2o_socket_loop_t *h2o_socket_loop_create(void)
{
    struct st_h2o_socket_loop_kqueue_t *loop = (struct st_h2o_socket_loop_kqueue_t*)create_socket_loop(
        sizeof(*loop),
        proceed,
        on_create,
        on_close);

    loop->kq = kqueue();

    return &loop->super;
}
