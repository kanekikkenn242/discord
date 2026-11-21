#pragma once
#include <stddef.h>
#include <stdint.h>

int zdma_gunzip(const uint8_t *input, size_t inputLength,
                uint8_t **output, size_t *outputLength);
int zdma_gzip(const uint8_t *input, size_t inputLength,
              uint8_t **output, size_t *outputLength);
void zdma_buffer_free(uint8_t *buffer);
