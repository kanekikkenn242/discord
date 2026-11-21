#include "gzip_bridge.h"

#include <stdlib.h>
#include <string.h>
#include <zlib.h>

/* gzip with deterministic header (mtime = 0, no name), matching Python's
   gzip.compress(mtime=0) used by scripts/pack3105.py. */
int zdma_gunzip(const uint8_t *input, size_t inputLength,
                uint8_t **output, size_t *outputLength) {
    if (!input || !output || !outputLength) return -1;
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, 15 + 16) != Z_OK) return -1;

    size_t capacity = inputLength * 4 + 4096;
    uint8_t *buffer = (uint8_t *)malloc(capacity);
    if (!buffer) { inflateEnd(&stream); return -1; }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)inputLength;
    stream.next_out = buffer;
    stream.avail_out = (uInt)capacity;

    int status = inflate(&stream, Z_FINISH);
    if (status != Z_STREAM_END) {
        free(buffer);
        inflateEnd(&stream);
        return -1;
    }
    *outputLength = (size_t)stream.total_out;
    *output = buffer;
    inflateEnd(&stream);
    return 0;
}

int zdma_gzip(const uint8_t *input, size_t inputLength,
              uint8_t **output, size_t *outputLength) {
    if (!input || !output || !outputLength) return -1;
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8,
                     Z_DEFAULT_STRATEGY) != Z_OK) return -1;

    uLong bound = compressBound((uLong)inputLength) + 64;
    uint8_t *buffer = (uint8_t *)malloc((size_t)bound);
    if (!buffer) { deflateEnd(&stream); return -1; }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)inputLength;
    stream.next_out = buffer;
    stream.avail_out = (uInt)bound;

    int status = deflate(&stream, Z_FINISH);
    if (status != Z_STREAM_END) {
        free(buffer);
        deflateEnd(&stream);
        return -1;
    }
    *outputLength = (size_t)stream.total_out;
    *output = buffer;
    deflateEnd(&stream);
    return 0;
}

void zdma_buffer_free(uint8_t *buffer) { free(buffer); }
