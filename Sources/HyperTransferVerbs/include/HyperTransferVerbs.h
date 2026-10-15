#ifndef HYPERTRANSFER_VERBS_H
#define HYPERTRANSFER_VERBS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ht_session ht_session;

int ht_claim_single(void);
int ht_single_is_held(void);
uint32_t ht_wire_len(uint32_t length);
int ht_gid_is_ipv4_mapped(const uint8_t raw[16]);
int ht_setup_record_ok(const void *bytes, uint32_t length);
ht_session *ht_open(const char *device);
void ht_close(ht_session *session);
const char *ht_last_error(ht_session *session);
int ht_exchange(ht_session *session, int wait_ms);
int ht_peer_lists(ht_session *session);
int ht_send(ht_session *session, const void *bytes, uint32_t length);
int ht_recv(ht_session *session, void *bytes, uint32_t length, int timeout_ms);

#ifdef __cplusplus
}
#endif

#endif
