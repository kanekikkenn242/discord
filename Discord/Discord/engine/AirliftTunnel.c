#include "AirliftTunnel.h"
#include "idevice.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

struct AirTunnel {
    struct AdapterHandle *adapter;
    struct RsdHandshakeHandle *handshake;
    struct AfcClientHandle *afc;
    int connected;
    char last_error[768];
};

static int fail_with_error(AirTunnel *tunnel, struct IdeviceFfiError *error, const char *operation) {
    if (tunnel == NULL) {
        if (error != NULL) {
            idevice_error_free(error);
        }
        return -1;
    }
    if (error == NULL) {
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "%s: unknown error", operation);
        return -1;
    }
    snprintf(
        tunnel->last_error,
        sizeof(tunnel->last_error),
        "%s: %s (code %d)",
        operation,
        error->message != NULL ? error->message : "unknown error",
        error->code
    );
    idevice_error_free(error);
    return -1;
}

static const char *failure_kind_text(enum TunnelFailureKind kind) {
    switch (kind) {
        case TunnelFailureNone:
            return "none";
        case TunnelFailureRsdUnreachable:
            return "RSD port unreachable";
        case TunnelFailurePairVerify:
            return "pair-verify refused";
        case TunnelFailureHostsRefused:
            return "candidate hosts refused";
        case TunnelFailureTimeout:
            return "timed out";
        case TunnelFailureTlsHandshake:
            return "TLS-PSK handshake failed";
        case TunnelFailureOther:
            return "RSD handshake or parse failure";
        default:
            return "unknown";
    }
}

AirTunnel *air_tunnel_create(void) {
    AirTunnel *tunnel = (AirTunnel *)calloc(1, sizeof(AirTunnel));
    if (tunnel != NULL) {
        tunnel->last_error[0] = '\0';
    }
    return tunnel;
}

void air_tunnel_destroy(AirTunnel *tunnel) {
    if (tunnel == NULL) {
        return;
    }
    if (tunnel->afc != NULL) {
        afc_client_free(tunnel->afc);
        tunnel->afc = NULL;
    }
    if (tunnel->handshake != NULL) {
        rsd_handshake_free(tunnel->handshake);
        tunnel->handshake = NULL;
    }
    if (tunnel->adapter != NULL) {
        adapter_free(tunnel->adapter);
        tunnel->adapter = NULL;
    }
    free(tunnel);
}

int air_tunnel_connect(
    AirTunnel *tunnel,
    const char *pairing_path,
    const char *host,
    uint16_t port,
    const char *extra_hosts_csv
) {
    if (tunnel == NULL) {
        return -1;
    }
    tunnel->last_error[0] = '\0';

    if (pairing_path == NULL || pairing_path[0] == '\0') {
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "no pairing file path");
        return -1;
    }
    if (access(pairing_path, R_OK) != 0) {
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "pairing file is not readable: %s", pairing_path);
        return -1;
    }

    struct RpPairingFileHandle *pairing_file = NULL;
    struct IdeviceFfiError *error = rp_pairing_file_read(pairing_path, &pairing_file);
    if (error != NULL) {
        return fail_with_error(tunnel, error, "read pairing file");
    }
    if (pairing_file == NULL) {
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "read pairing file: empty result");
        return -1;
    }

    const char *address = (host != NULL && host[0] != '\0') ? host : "10.7.0.1";
    uint16_t actual_port = port == 0 ? 49152 : port;

    struct sockaddr_in socket_address;
    memset(&socket_address, 0, sizeof(socket_address));
    socket_address.sin_len = sizeof(socket_address);
    socket_address.sin_family = AF_INET;
    socket_address.sin_port = htons(actual_port);

    if (inet_pton(AF_INET, address, &socket_address.sin_addr) != 1) {
        rp_pairing_file_free(pairing_file);
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "invalid IPv4 host: %s", address);
        return -1;
    }

    const char *extra_hosts[16];
    size_t extra_count = 0;
    char *extra_copy = NULL;

    if (extra_hosts_csv != NULL && extra_hosts_csv[0] != '\0') {
        extra_copy = strdup(extra_hosts_csv);
        if (extra_copy != NULL) {
            char *save = NULL;
            char *token = strtok_r(extra_copy, ",", &save);
            while (token != NULL && extra_count < 16) {
                while (*token == ' ' || *token == '\t') {
                    token++;
                }
                if (*token != '\0') {
                    extra_hosts[extra_count++] = token;
                }
                token = strtok_r(NULL, ",", &save);
            }
        }
    }

    enum TunnelFailureKind failure_kind = TunnelFailureNone;
    struct AdapterHandle *adapter = NULL;
    struct RsdHandshakeHandle *handshake = NULL;

    error = tunnel_create_rppairing_multihost(
        (const idevice_sockaddr *)&socket_address,
        (idevice_socklen_t)sizeof(socket_address),
        "Discord",
        pairing_file,
        NULL,
        NULL,
        extra_count > 0 ? (const char *const *)extra_hosts : NULL,
        extra_count,
        &failure_kind,
        &adapter,
        &handshake
    );

    rp_pairing_file_free(pairing_file);
    if (extra_copy != NULL) {
        free(extra_copy);
    }

    if (error != NULL) {
        fail_with_error(tunnel, error, "open RSD tunnel");
        if (failure_kind != TunnelFailureNone) {
            size_t used = strlen(tunnel->last_error);
            snprintf(
                tunnel->last_error + used,
                sizeof(tunnel->last_error) - used,
                " [stage: %s]",
                failure_kind_text(failure_kind)
            );
        }
        if (adapter != NULL) {
            adapter_free(adapter);
        }
        if (handshake != NULL) {
            rsd_handshake_free(handshake);
        }
        return -1;
    }

    if (adapter == NULL || handshake == NULL) {
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "tunnel returned no adapter/handshake");
        if (adapter != NULL) {
            adapter_free(adapter);
        }
        if (handshake != NULL) {
            rsd_handshake_free(handshake);
        }
        return -1;
    }

    tunnel->adapter = adapter;
    tunnel->handshake = handshake;
    tunnel->connected = 1;
    return 0;
}

int air_tunnel_vend_container(AirTunnel *tunnel, const char *bundle_id) {
    if (tunnel == NULL || bundle_id == NULL || bundle_id[0] == '\0') {
        return -1;
    }
    if (!tunnel->connected || tunnel->adapter == NULL || tunnel->handshake == NULL) {
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "tunnel is not connected");
        return -1;
    }
    tunnel->last_error[0] = '\0';

    if (tunnel->afc != NULL) {
        afc_client_free(tunnel->afc);
        tunnel->afc = NULL;
    }

    struct HouseArrestClientHandle *house_arrest = NULL;
    struct IdeviceFfiError *error = house_arrest_client_connect_rsd(
        tunnel->adapter,
        tunnel->handshake,
        &house_arrest
    );
    if (error != NULL) {
        return fail_with_error(tunnel, error, "connect House Arrest");
    }
    if (house_arrest == NULL) {
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "connect House Arrest: empty handle");
        return -1;
    }

    // vend_container consumes the House Arrest client, even on failure.
    error = house_arrest_vend_container(house_arrest, bundle_id, &tunnel->afc);
    house_arrest = NULL;

    if (error != NULL) {
        return fail_with_error(tunnel, error, "vend container");
    }
    if (tunnel->afc == NULL) {
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "vend container: AFC handle is NULL");
        return -1;
    }
    return 0;
}

int air_tunnel_read_file(
    AirTunnel *tunnel,
    const char *path,
    uint8_t **data,
    size_t *length
) {
    if (tunnel == NULL || path == NULL || data == NULL || length == NULL) {
        return -1;
    }
    *data = NULL;
    *length = 0;

    if (tunnel->afc == NULL) {
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "AFC is not connected");
        return -1;
    }
    tunnel->last_error[0] = '\0';

    struct AfcFileHandle *file = NULL;
    struct IdeviceFfiError *error = afc_file_open(tunnel->afc, path, AfcRdOnly, &file);
    if (error != NULL) {
        return fail_with_error(tunnel, error, "open file for read");
    }
    if (file == NULL) {
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "open file for read: empty handle");
        return -1;
    }

    error = afc_file_read_entire(file, data, length);
    afc_file_close(file);

    if (error != NULL) {
        *data = NULL;
        *length = 0;
        return fail_with_error(tunnel, error, "read file");
    }
    return 0;
}

int air_tunnel_file_exists(AirTunnel *tunnel, const char *path) {
    if (tunnel == NULL || path == NULL || tunnel->afc == NULL) {
        return 0;
    }

    struct AfcFileInfo info;
    memset(&info, 0, sizeof(info));
    struct IdeviceFfiError *error = afc_get_file_info(tunnel->afc, path, &info);
    if (error != NULL) {
        idevice_error_free(error);
        return 0;
    }
    afc_file_info_free(&info);
    return 1;
}

int air_tunnel_remove_file(AirTunnel *tunnel, const char *path) {
    if (tunnel == NULL || path == NULL || tunnel->afc == NULL) {
        return -1;
    }
    tunnel->last_error[0] = '\0';
    struct IdeviceFfiError *error = afc_remove_path(tunnel->afc, path);
    if (error != NULL) {
        return fail_with_error(tunnel, error, "remove file");
    }
    return 0;
}

int air_tunnel_write_file(
    AirTunnel *tunnel,
    const char *path,
    const uint8_t *data,
    size_t length
) {
    if (tunnel == NULL || path == NULL || (length > 0 && data == NULL)) {
        return -1;
    }
    if (tunnel->afc == NULL) {
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "AFC is not connected");
        return -1;
    }
    tunnel->last_error[0] = '\0';

    char old_path[4096];
    int written = snprintf(old_path, sizeof(old_path), "%s.discord-old", path);
    if (written < 0 || (size_t)written >= sizeof(old_path)) {
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "path is too long");
        return -1;
    }

    // A stale temp file from an interrupted transfer is harmless.
    struct IdeviceFfiError *stale = afc_remove_path(tunnel->afc, old_path);
    if (stale != NULL) {
        idevice_error_free(stale);
    }

    struct IdeviceFfiError *error = afc_rename_path(tunnel->afc, path, old_path);
    if (error != NULL) {
        return fail_with_error(tunnel, error, "stage original");
    }

    struct AfcFileHandle *file = NULL;
    error = afc_file_open(tunnel->afc, path, AfcWrOnly, &file);
    if (error != NULL) {
        afc_rename_path(tunnel->afc, old_path, path);
        return fail_with_error(tunnel, error, "create replacement");
    }
    if (file == NULL) {
        afc_rename_path(tunnel->afc, old_path, path);
        snprintf(tunnel->last_error, sizeof(tunnel->last_error), "create replacement: empty handle");
        return -1;
    }

    error = afc_file_write(file, data, length);
    struct IdeviceFfiError *close_error = afc_file_close(file);

    if (error != NULL) {
        afc_remove_path(tunnel->afc, path);
        afc_rename_path(tunnel->afc, old_path, path);
        return fail_with_error(tunnel, error, "write replacement");
    }
    if (close_error != NULL) {
        afc_remove_path(tunnel->afc, path);
        afc_rename_path(tunnel->afc, old_path, path);
        return fail_with_error(tunnel, close_error, "close replacement");
    }

    uint8_t *verify = NULL;
    size_t verify_length = 0;
    if (air_tunnel_read_file(tunnel, path, &verify, &verify_length) != 0) {
        afc_remove_path(tunnel->afc, path);
        afc_rename_path(tunnel->afc, old_path, path);
        return -1;
    }

    int matches = verify_length == length;
    if (matches && length > 0) {
        matches = memcmp(verify, data, length) == 0;
    }
    air_tunnel_free_data(verify, verify_length);

    if (!matches) {
        struct IdeviceFfiError *removed = afc_remove_path(tunnel->afc, path);
        if (removed != NULL) {
            idevice_error_free(removed);
        }
        afc_rename_path(tunnel->afc, old_path, path);
        snprintf(
            tunnel->last_error,
            sizeof(tunnel->last_error),
            "written file did not match package bytes; original restored"
        );
        return -1;
    }

    // The original is no longer needed. A failure here only wastes space.
    struct IdeviceFfiError *remove_error = afc_remove_path(tunnel->afc, old_path);
    if (remove_error != NULL) {
        idevice_error_free(remove_error);
    }
    return 0;
}

void air_tunnel_free_data(uint8_t *data, size_t length) {
    if (data != NULL) {
        afc_file_read_data_free(data, length);
    }
}

const char *air_tunnel_last_error(AirTunnel *tunnel) {
    if (tunnel == NULL) {
        return "tunnel is NULL";
    }
    return tunnel->last_error;
}
