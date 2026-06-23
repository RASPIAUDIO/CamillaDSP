#pragma once

#if !PICO_NO_HARDWARE
#include "hardware/clocks.h"
#include "hardware/pio.h"
#endif

#define spdif_tx_wrap_target 0
#define spdif_tx_wrap 0

static const uint16_t spdif_tx_program_instructions[] = {
    0x6001, /* out pins, 1 */
};

#if !PICO_NO_HARDWARE
static const struct pio_program spdif_tx_program = {
    .instructions = spdif_tx_program_instructions,
    .length = 1,
    .origin = -1,
};

static inline pio_sm_config spdif_tx_program_get_default_config(uint offset)
{
    pio_sm_config c = pio_get_default_sm_config();
    sm_config_set_wrap(&c, offset + spdif_tx_wrap_target, offset + spdif_tx_wrap);
    return c;
}

static inline void spdif_tx_program_init(PIO pio, uint sm, uint offset, uint gpio, float bit_rate, uint32_t pio_clock_hz)
{
    pio_gpio_init(pio, gpio);
    pio_sm_set_consecutive_pindirs(pio, sm, gpio, 1, true);

    pio_sm_config c = spdif_tx_program_get_default_config(offset);
    sm_config_set_out_pins(&c, gpio, 1);
    sm_config_set_out_shift(&c, false, true, 32);
    sm_config_set_fifo_join(&c, PIO_FIFO_JOIN_TX);
    sm_config_set_clkdiv(&c, (float)pio_clock_hz / bit_rate);

    pio_sm_init(pio, sm, offset, &c);
    pio_sm_set_enabled(pio, sm, true);
}
#endif
