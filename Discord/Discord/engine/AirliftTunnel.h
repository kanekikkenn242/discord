#ifndef AIRLIFT_TUNNEL_H
#define AIRLIFT_TUNNEL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AirTunnel AirTunnel;

AirTunnel *air_tunnel_create(void);
void air_tunnel_destroy(AirTunnel *tunnel);

int air_tunnel_connect(
    AirTunnel *tunnel,
    const char *pairing_path,
    const char *host,
    uint16_t port,
    const char *extra_hosts_csv
);

int air_tunnel_vend_container(AirTunnel *tunnel, const char *bundle_id);

int air_tunnel_read_file(
    AirTunnel *tunnel,
    const char *path,
    uint8_t **data,
    size_t *length
);

int air_tunnel_write_file(
    AirTunnel *tunnel,
    const char *path,
    const uint8_t *data,
    size_t length
);

int air_tunnel_file_exists(AirTunnel *tunnel, const char *path);
int air_tunnel_remove_file(AirTunnel *tunnel, const char *path);
void air_tunnel_free_data(uint8_t *data, size_t length);
const char *air_tunnel_last_error(AirTunnel *tunnel);

#ifdef __cplusplus
}
#endif

#endif /* AIRLIFT_TUNNEL_H */
