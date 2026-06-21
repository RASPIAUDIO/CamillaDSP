CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11
LDFLAGS ?=
LDLIBS ?=

BUILD_DIR := build
SRC_DIR := src

GEN_SRCS := $(SRC_DIR)/spdif_gen.c $(SRC_DIR)/spdif_bmc.c
PIO_SRCS := $(SRC_DIR)/spdif_pi5_pio_tx.c $(SRC_DIR)/spdif_bmc.c

PIOLIB_INC ?= /usr/local/include/piolib
PIOLIB_LIB ?= /usr/local/lib

.PHONY: all clean pio

all: $(BUILD_DIR)/spdif_gen

pio: CFLAGS += -DHAVE_PIOLIB -I$(PIOLIB_INC)
pio: LDFLAGS += -L$(PIOLIB_LIB)
pio: LDLIBS += -lpio
pio: $(BUILD_DIR)/spdif_pi5_pio_tx

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/spdif_gen: $(GEN_SRCS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $@ $(GEN_SRCS) $(LDFLAGS) $(LDLIBS) -lm

$(BUILD_DIR)/spdif_pi5_pio_tx: $(PIO_SRCS) $(SRC_DIR)/spdif_tx.pio.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $@ $(PIO_SRCS) $(LDFLAGS) $(LDLIBS) -lm

clean:
	rm -rf $(BUILD_DIR)
