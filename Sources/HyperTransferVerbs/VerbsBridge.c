#include "HyperTransferVerbs.h"

#include <arpa/inet.h>
#include <errno.h>
#include <ifaddrs.h>
#include <infiniband/verbs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

#define HT_SETUP_LEN 64
#define HT_SETUP_PORT 24764
#define HT_WIRE_UNIT 4096
#define HT_BUFFER (1024 * 1024)

struct ht_hello {
    char magic[4];
    uint8_t gid[16];
    uint32_t qpn;
    uint32_t psn;
    uint16_t lid;
    uint16_t gid_index;
    uint8_t pad[32];
};

_Static_assert(sizeof(struct ht_hello) == HT_SETUP_LEN, "queue-pair record is 64 bytes");

struct ht_session {
    struct ibv_context *context;
    struct ibv_pd *pd;
    struct ibv_cq *cq;
    struct ibv_qp *qp;
    struct ibv_mr *send_mr;
    struct ibv_mr *recv_mr;
    void *send_buf;
    void *recv_buf;
    uint32_t psn;
    uint16_t lid;
    uint16_t sgid_index;
    int ipv4_mapped;
    union ibv_gid gid;
    int fd;
    int connected;
    int rts;
    int peer_lists;
    uint32_t peer_qpn;
    int recv_posted;
    int recv_ready;
    uint32_t posted_wire;
    char error[256];
};

static char open_error[256] = "The verbs device did not open.";
static int lock_fd = -1;

static int lock_path(char *path, size_t cap) {
    const char *home = getenv("HOME");
    if (!home || home[0] == '\0') {
        return snprintf(path, cap, "/tmp/hypertransfer-%d.lock", getuid()) > 0 ? 0 : -1;
    }
    snprintf(path, cap, "%s/Library", home);
    mkdir(path, 0755);
    snprintf(path, cap, "%s/Library/Application Support", home);
    mkdir(path, 0755);
    snprintf(path, cap, "%s/Library/Application Support/HyperTransfer", home);
    mkdir(path, 0755);
    return snprintf(path, cap, "%s/Library/Application Support/HyperTransfer/instance.lock", home) > 0 ? 0 : -1;
}

static int try_lock(int keep) {
    char path[1024];
    if (lock_path(path, sizeof path) != 0) return -1;
    int fd = open(path, O_CREAT | O_RDWR, 0644);
    if (fd < 0) return -1;
    if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
        close(fd);
        return 1;
    }
    if (keep) lock_fd = fd;
    else close(fd);
    return 0;
}

int ht_claim_single(void) {
    if (lock_fd >= 0) return 0;
    return try_lock(1);
}

int ht_single_is_held(void) {
    if (lock_fd < 0) return 0;
    return try_lock(0) == 1 ? 1 : 0;
}

static void set_error(ht_session *session, const char *text) {
    if (!session) {
        snprintf(open_error, sizeof open_error, "%s", text);
        return;
    }
    snprintf(session->error, sizeof session->error, "%s", text);
}

static uint32_t wire_len(uint32_t length) {
    if (length == 0) return HT_WIRE_UNIT;
    uint32_t rounded = (length + (HT_WIRE_UNIT - 1)) & ~(uint32_t)(HT_WIRE_UNIT - 1);
    return rounded == 0 ? HT_WIRE_UNIT : rounded;
}

static int hello_ok(const struct ht_hello *hello, const char magic[4]);

uint32_t ht_wire_len(uint32_t length) {
    return wire_len(length);
}

int ht_setup_record_ok(const void *bytes, uint32_t length) {
    if (!bytes || length != HT_SETUP_LEN) return 0;
    return hello_ok((const struct ht_hello *)bytes, "HTQ1");
}

int ht_gid_is_ipv4_mapped(const uint8_t raw[16]) {
    if (!raw) return 0;
    for (int i = 0; i < 10; i++) {
        if (raw[i] != 0) return 0;
    }
    return raw[10] == 0xff && raw[11] == 0xff;
}

static int gid_is_zero(union ibv_gid gid) {
    for (int i = 0; i < 16; i++) {
        if (gid.raw[i] != 0) return 0;
    }
    return 1;
}

const char *ht_last_error(ht_session *session) {
    if (!session) return open_error;
    if (session->error[0] == '\0') return "The queue pair stopped.";
    return session->error;
}

static int poll_kind(ht_session *session, int want_recv, int timeout_ms) {
    int waited = 0;
    for (;;) {
        if (want_recv && session->recv_ready) return 0;
        struct ibv_wc wc;
        int n = ibv_poll_cq(session->cq, 1, &wc);
        if (n < 0) {
            set_error(session, "The completion queue could not be read.");
            return -1;
        }
        if (n == 0) {
            if (waited >= timeout_ms) return 1;
            usleep(20000);
            waited += 20;
            continue;
        }
        if (wc.status != IBV_WC_SUCCESS) {
            set_error(session, "The queue pair reported a failed completion.");
            return -1;
        }
        int is_recv = wc.opcode == IBV_WC_RECV;
        if (is_recv) {
            session->recv_posted = 0;
            session->recv_ready = 1;
            if (want_recv) return 0;
            continue;
        }
        if (!want_recv) return 0;
    }
}

static int post_recv(ht_session *session, uint32_t wire) {
    if (wire > HT_BUFFER) {
        set_error(session, "The receive is larger than the registered window.");
        return -1;
    }
    memset(session->recv_buf, 0, wire);
    struct ibv_sge sge = {
        .addr = (uintptr_t)session->recv_buf,
        .length = wire,
        .lkey = session->recv_mr->lkey,
    };
    struct ibv_recv_wr wr = {
        .wr_id = 1,
        .sg_list = &sge,
        .num_sge = 1,
    };
    struct ibv_recv_wr *bad = NULL;
    if (ibv_post_recv(session->qp, &wr, &bad)) {
        set_error(session, "The receive could not be posted.");
        return -1;
    }
    session->recv_posted = 1;
    session->posted_wire = wire;
    return 0;
}

int ht_send(ht_session *session, const void *bytes, uint32_t length) {
    if (!session || !session->connected) {
        set_error(session, "The queue pair is not up.");
        return -1;
    }
    uint32_t wire = wire_len(length);
    if (wire > HT_BUFFER || length > HT_BUFFER) {
        set_error(session, "The send is larger than the registered window.");
        return -1;
    }
    memset(session->send_buf, 0, wire);
    if (length > 0 && bytes) memcpy(session->send_buf, bytes, length);
    struct ibv_sge sge = {
        .addr = (uintptr_t)session->send_buf,
        .length = wire,
        .lkey = session->send_mr->lkey,
    };
    struct ibv_send_wr wr = {
        .wr_id = 2,
        .sg_list = &sge,
        .num_sge = 1,
        .opcode = IBV_WR_SEND,
        .send_flags = IBV_SEND_SIGNALED,
    };
    struct ibv_send_wr *bad = NULL;
    if (ibv_post_send(session->qp, &wr, &bad)) {
        set_error(session, "The send could not be posted.");
        return -1;
    }
    if (poll_kind(session, 0, 60000) != 0) {
        if (session->error[0] == '\0') set_error(session, "The send did not complete.");
        return -1;
    }
    return 0;
}

int ht_recv(ht_session *session, void *bytes, uint32_t length, int timeout_ms) {
    if (!session || !session->connected) {
        set_error(session, "The queue pair is not up.");
        return -1;
    }
    uint32_t wire = wire_len(length);
    if (wire > HT_BUFFER || length > HT_BUFFER) {
        set_error(session, "The receive is larger than the registered window.");
        return -1;
    }
    if (session->recv_ready && session->posted_wire != wire) {
        set_error(session, "A completion arrived for a different message size.");
        return -1;
    }
    if (!session->recv_ready) {
        if (session->recv_posted && session->posted_wire != wire) {
            set_error(session, "A receive is already posted for a different message size.");
            return -1;
        }
        if (!session->recv_posted && post_recv(session, wire) != 0) return -1;
        int waited = timeout_ms < 0 ? 600000 : timeout_ms;
        int rc = poll_kind(session, 1, waited);
        if (rc != 0) return rc;
    }
    if (bytes && length > 0) memcpy(bytes, session->recv_buf, length);
    session->recv_ready = 0;
    return 0;
}

static int fill_hello(ht_session *session, struct ht_hello *hello, const char magic[4]) {
    memset(hello, 0, sizeof *hello);
    memcpy(hello->magic, magic, 4);
    memcpy(hello->gid, &session->gid, 16);
    hello->qpn = session->qp->qp_num;
    hello->psn = session->psn;
    hello->lid = session->lid;
    hello->gid_index = session->sgid_index;
    hello->pad[0] = 1;
    return 0;
}

static int hello_ok(const struct ht_hello *hello, const char magic[4]) {
    return memcmp(hello->magic, magic, 4) == 0;
}

static int bind_bridge(ht_session *session) {
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) {
        set_error(session, "The Thunderbolt bridge address could not be read.");
        return -1;
    }
    struct sockaddr_in6 local;
    memset(&local, 0, sizeof local);
    int found = 0;
    unsigned int index = if_nametoindex("bridge0");
    for (struct ifaddrs *ifa = list; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || strcmp(ifa->ifa_name, "bridge0") != 0) continue;
        if (ifa->ifa_addr->sa_family != AF_INET6) continue;
        struct sockaddr_in6 *sin = (struct sockaddr_in6 *)ifa->ifa_addr;
        if (!IN6_IS_ADDR_LINKLOCAL(&sin->sin6_addr)) continue;
        local = *sin;
        found = 1;
        break;
    }
    freeifaddrs(list);
    if (!found || index == 0) {
        set_error(session, "The Thunderbolt bridge has no link-local address for the queue-pair record.");
        return -1;
    }
    int fd = socket(AF_INET6, SOCK_DGRAM, 0);
    if (fd < 0) {
        set_error(session, "The queue-pair record socket did not open.");
        return -1;
    }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    setsockopt(fd, IPPROTO_IPV6, IPV6_BOUND_IF, &index, sizeof index);
    setsockopt(fd, IPPROTO_IPV6, IPV6_MULTICAST_IF, &index, sizeof index);
    int loop = 0;
    setsockopt(fd, IPPROTO_IPV6, IPV6_MULTICAST_LOOP, &loop, sizeof loop);
    local.sin6_port = htons(HT_SETUP_PORT);
    local.sin6_scope_id = index;
    if (bind(fd, (struct sockaddr *)&local, sizeof local) != 0) {
        int err = errno;
        close(fd);
        if (err == EPERM || err == EACCES) {
            set_error(session, "macOS has not allowed the incoming connection yet.");
        } else {
            set_error(session, "The queue-pair record socket did not bind on the Thunderbolt bridge.");
        }
        return -1;
    }
    struct ipv6_mreq group;
    memset(&group, 0, sizeof group);
    inet_pton(AF_INET6, "ff02::1", &group.ipv6mr_multiaddr);
    group.ipv6mr_interface = index;
    setsockopt(fd, IPPROTO_IPV6, IPV6_JOIN_GROUP, &group, sizeof group);
    struct timeval tv = {.tv_sec = 0, .tv_usec = 200000};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    session->fd = fd;
    return 0;
}

static int send_hello(ht_session *session, const struct ht_hello *hello) {
    struct sockaddr_in6 dest;
    memset(&dest, 0, sizeof dest);
    dest.sin6_family = AF_INET6;
    dest.sin6_port = htons(HT_SETUP_PORT);
    dest.sin6_scope_id = if_nametoindex("bridge0");
    inet_pton(AF_INET6, "ff02::1", &dest.sin6_addr);
    ssize_t n = sendto(session->fd, hello, HT_SETUP_LEN, 0, (struct sockaddr *)&dest, sizeof dest);
    if (n != HT_SETUP_LEN) {
        int err = errno;
        if (session->fd >= 0) {
            close(session->fd);
            session->fd = -1;
        }
        if (err == EPERM || err == EACCES) {
            set_error(session, "macOS has not allowed the incoming connection yet.");
        } else {
            set_error(session, "The queue-pair record was not sent.");
        }
        return -1;
    }
    return 0;
}

static int recv_hello(ht_session *session, struct ht_hello *hello) {
    struct sockaddr_in6 from;
    socklen_t len = sizeof from;
    ssize_t n = recvfrom(session->fd, hello, HT_SETUP_LEN, 0, (struct sockaddr *)&from, &len);
    if (n < 0) return 1;
    if (n != HT_SETUP_LEN) return 1;
    return 0;
}

static int move_to_rts(ht_session *session, const struct ht_hello *peer) {
    struct ibv_qp_attr attr;
    memset(&attr, 0, sizeof attr);
    attr.qp_state = IBV_QPS_RTR;
    attr.path_mtu = IBV_MTU_4096;
    attr.dest_qp_num = peer->qpn;
    attr.rq_psn = peer->psn;
    attr.ah_attr.dlid = peer->lid;
    attr.ah_attr.port_num = 1;
    attr.ah_attr.is_global = 1;
    attr.ah_attr.grh.hop_limit = 1;
    attr.ah_attr.grh.sgid_index = session->sgid_index;
    memcpy(&attr.ah_attr.grh.dgid, peer->gid, 16);
    int flags = IBV_QP_STATE | IBV_QP_AV | IBV_QP_PATH_MTU | IBV_QP_DEST_QPN | IBV_QP_RQ_PSN;
    if (ibv_modify_qp(session->qp, &attr, flags)) {
        int err = errno;
        snprintf(session->error, sizeof session->error,
            "The queue pair reached the peer and was not made ready to receive (%s).", strerror(err));
        return -1;
    }
    memset(&attr, 0, sizeof attr);
    attr.qp_state = IBV_QPS_RTS;
    attr.sq_psn = session->psn;
    if (ibv_modify_qp(session->qp, &attr, IBV_QP_STATE | IBV_QP_SQ_PSN)) {
        set_error(session, "The queue pair did not become ready to send.");
        return -1;
    }
    return 0;
}

static int restore_init(ht_session *session) {
    struct ibv_qp_attr attr;
    memset(&attr, 0, sizeof attr);
    attr.qp_state = IBV_QPS_RESET;
    if (ibv_modify_qp(session->qp, &attr, IBV_QP_STATE)) return -1;
    memset(&attr, 0, sizeof attr);
    attr.qp_state = IBV_QPS_INIT;
    attr.pkey_index = 0;
    attr.port_num = 1;
    attr.qp_access_flags = 0;
    if (ibv_modify_qp(session->qp, &attr, IBV_QP_STATE | IBV_QP_PKEY_INDEX | IBV_QP_PORT | IBV_QP_ACCESS_FLAGS)) {
        return -1;
    }
    return 0;
}

static int meet_peer(ht_session *session, struct ht_hello *peer) {
    int later = session->qp->qp_num > peer->qpn
        || (session->qp->qp_num == peer->qpn && memcmp(session->gid.raw, peer->gid, 16) > 0);
    if (later) usleep(400000);
    for (int attempt = 0; attempt < 2; attempt++) {
        struct ht_hello incoming;
        if (session->fd >= 0 && recv_hello(session, &incoming) == 0
            && hello_ok(&incoming, "HTQ1") && incoming.qpn != session->qp->qp_num) {
            *peer = incoming;
            session->peer_lists = incoming.pad[0] != 0;
        }
        if (move_to_rts(session, peer) == 0) return 0;
        if (restore_init(session) != 0) return -1;
        if (attempt + 1 < 2) usleep(150000);
    }
    return 1;
}

int ht_peer_lists(ht_session *session) {
    return session && session->peer_lists ? 1 : 0;
}

int ht_exchange(ht_session *session, int wait_ms) {
    if (!session) return -1;
    if (session->connected) return 0;
    if (session->fd < 0 && bind_bridge(session) != 0) return 2;
    struct ht_hello mine;
    if (!session->rts) {
        fill_hello(session, &mine, "HTQ1");
        if (send_hello(session, &mine) != 0) return 2;
        int waited = 0;
        struct ht_hello peer;
        int have_peer = 0;
        while (waited < wait_ms) {
            struct ht_hello incoming;
            int rc = recv_hello(session, &incoming);
            if (rc == 0 && hello_ok(&incoming, "HTQ1") && incoming.qpn != session->qp->qp_num) {
                peer = incoming;
                have_peer = 1;
                session->peer_lists = incoming.pad[0] != 0;
                break;
            }
            usleep(20000);
            waited += 20;
        }
        if (!have_peer) return 1;
        int met = meet_peer(session, &peer);
        if (met < 0) return -1;
        if (met > 0) return 2;
        session->rts = 1;
        session->peer_qpn = peer.qpn;
    }
    if (session->fd < 0 && bind_bridge(session) != 0) return 2;
    struct ht_hello go;
    fill_hello(session, &go, "HTGO");
    int go_seen = 0;
    int go_waited = 0;
    while (go_waited < wait_ms) {
        if (send_hello(session, &go) != 0) return 2;
        struct ht_hello incoming;
        if (recv_hello(session, &incoming) == 0) {
            if (hello_ok(&incoming, "HTGO") && incoming.qpn == session->peer_qpn) {
                go_seen = 1;
                break;
            }
            if (hello_ok(&incoming, "HTQ1") && incoming.qpn != session->qp->qp_num) {
                session->rts = 0;
                session->peer_lists = incoming.pad[0] != 0;
                if (restore_init(session) != 0) return -1;
                int met = meet_peer(session, &incoming);
                if (met < 0) return -1;
                if (met > 0) return 2;
                session->rts = 1;
                session->peer_qpn = incoming.qpn;
                go_waited = 0;
                continue;
            }
        }
        usleep(20000);
        go_waited += 20;
    }
    if (!go_seen) {
        session->rts = 0;
        if (restore_init(session) != 0) return -1;
        set_error(session, "The peer queue pair did not answer.");
        return 1;
    }
    close(session->fd);
    session->fd = -1;
    session->connected = 1;
    return 0;
}

static void *aligned_buffer(void) {
    long page = sysconf(_SC_PAGESIZE);
    if (page < HT_WIRE_UNIT) page = HT_WIRE_UNIT;
    void *buffer = NULL;
    if (posix_memalign(&buffer, (size_t)page, HT_BUFFER) != 0) return NULL;
    memset(buffer, 0, HT_BUFFER);
    return buffer;
}

ht_session *ht_open(const char *device) {
    if (ht_claim_single() != 0) {
        set_error(NULL, "HyperTransfer is already open.");
        return NULL;
    }
    if (!device || device[0] == '\0') {
        set_error(NULL, "No active verbs device was named.");
        return NULL;
    }
    struct ibv_device **list = ibv_get_device_list(NULL);
    if (!list) {
        set_error(NULL, "The verbs device list could not be read.");
        return NULL;
    }
    struct ibv_device *found = NULL;
    for (int i = 0; list[i]; i++) {
        if (strcmp(ibv_get_device_name(list[i]), device) == 0) found = list[i];
    }
    if (!found) {
        ibv_free_device_list(list);
        set_error(NULL, "The named verbs device is not in the device list.");
        return NULL;
    }
    struct ibv_context *context = ibv_open_device(found);
    ibv_free_device_list(list);
    if (!context) {
        set_error(NULL, "The verbs device did not open.");
        return NULL;
    }
    ht_session *session = calloc(1, sizeof *session);
    if (!session) {
        ibv_close_device(context);
        set_error(NULL, "The queue pair session could not be allocated.");
        return NULL;
    }
    session->context = context;
    session->fd = -1;
    struct ibv_port_attr port;
    memset(&port, 0, sizeof port);
    if (ibv_query_port(context, 1, &port) || port.state != IBV_PORT_ACTIVE) {
        set_error(session, "The verbs port is not ACTIVE.");
        ht_close(session);
        return NULL;
    }
    session->lid = port.lid;
    union ibv_gid fallback;
    int fallback_index = -1;
    memset(&fallback, 0, sizeof fallback);
    for (int i = 0; i < 4; i++) {
        union ibv_gid gid;
        if (ibv_query_gid(context, 1, i, &gid) || gid_is_zero(gid)) continue;
        if (ht_gid_is_ipv4_mapped(gid.raw)) {
            session->gid = gid;
            session->sgid_index = (uint16_t)i;
            session->ipv4_mapped = 1;
            fallback_index = i;
            break;
        }
        if (fallback_index < 0) {
            fallback = gid;
            fallback_index = i;
        }
    }
    if (!session->ipv4_mapped) {
        if (fallback_index < 0) {
            set_error(session, "The verbs port has no GID.");
            ht_close(session);
            return NULL;
        }
        session->gid = fallback;
        session->sgid_index = (uint16_t)fallback_index;
    }
    session->pd = ibv_alloc_pd(context);
    session->send_buf = aligned_buffer();
    session->recv_buf = aligned_buffer();
    if (!session->pd || !session->send_buf || !session->recv_buf) {
        set_error(session, "The registered window could not be allocated.");
        ht_close(session);
        return NULL;
    }
    session->send_mr = ibv_reg_mr(session->pd, session->send_buf, HT_BUFFER, IBV_ACCESS_LOCAL_WRITE);
    session->recv_mr = ibv_reg_mr(session->pd, session->recv_buf, HT_BUFFER, IBV_ACCESS_LOCAL_WRITE);
    session->cq = ibv_create_cq(context, 4096, NULL, NULL, 0);
    if (!session->send_mr || !session->recv_mr || !session->cq) {
        set_error(session, "The verbs window or completion queue was not created.");
        ht_close(session);
        return NULL;
    }
    struct ibv_qp_init_attr init;
    memset(&init, 0, sizeof init);
    init.send_cq = session->cq;
    init.recv_cq = session->cq;
    init.cap.max_send_wr = 4095;
    init.cap.max_recv_wr = 4095;
    init.cap.max_send_sge = 1;
    init.cap.max_recv_sge = 1;
    init.qp_type = IBV_QPT_UC;
    session->qp = ibv_create_qp(session->pd, &init);
    if (!session->qp) {
        set_error(session, "The queue pair was not created.");
        ht_close(session);
        return NULL;
    }
    struct ibv_qp_attr attr;
    memset(&attr, 0, sizeof attr);
    attr.qp_state = IBV_QPS_INIT;
    attr.pkey_index = 0;
    attr.port_num = 1;
    attr.qp_access_flags = 0;
    if (ibv_modify_qp(session->qp, &attr, IBV_QP_STATE | IBV_QP_PKEY_INDEX | IBV_QP_PORT | IBV_QP_ACCESS_FLAGS)) {
        set_error(session, "The queue pair did not enter INIT.");
        ht_close(session);
        return NULL;
    }
    session->psn = (uint32_t)arc4random_uniform(0xFFFFFF);
    return session;
}

void ht_close(ht_session *session) {
    if (!session) return;
    if (session->fd >= 0) close(session->fd);
    if (session->qp) ibv_destroy_qp(session->qp);
    if (session->cq) ibv_destroy_cq(session->cq);
    if (session->send_mr) ibv_dereg_mr(session->send_mr);
    if (session->recv_mr) ibv_dereg_mr(session->recv_mr);
    if (session->pd) ibv_dealloc_pd(session->pd);
    if (session->context) ibv_close_device(session->context);
    free(session->send_buf);
    free(session->recv_buf);
    free(session);
}
