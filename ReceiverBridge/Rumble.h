// Xbox HID output report 3 -> Xbox 360 USB motor command.
// Protocol references: Chromium xbox_hid_controller.cc and Linux xpad.c.
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <math.h>

typedef struct {
    uint8_t low, high;
    double on, delay;
    unsigned cycles;
} RumbleEffect;

static int decodeRumble(uint32_t reportID, const uint8_t *p, size_t n, RumbleEffect *effect) {
    if (reportID != 3 || !p || !effect) return 0;
    if (n == 9) { if (*p++ != 3) return 0; n--; }
    if (n != 8 || (p[0] & 0xf0)) return 0;
    // Mask: bit 1 = low-frequency body motor; bit 0 = high-frequency.
    // Trigger motors are absent on this receiver and are not synthesized.
    *effect = (RumbleEffect){
        .low = (p[0] & 2) ? (uint8_t)((p[3] > 100 ? 100 : p[3]) * 255u / 100u) : 0,
        .high = (p[0] & 1) ? (uint8_t)((p[4] > 100 ? 100 : p[4]) * 255u / 100u) : 0,
        .on = p[5] * .01, .delay = p[6] * .01, .cycles = (unsigned)p[7] + 1
    };
    return 1;
}

static void encodeRumble(uint8_t low, uint8_t high, uint8_t out[8]) {
    const uint8_t packet[] = {0, 8, 0, low, high, 0, 0, 0};
    memcpy(out, packet, sizeof(packet));
}

static void rumbleAt(RumbleEffect effect, double elapsed, uint8_t *low, uint8_t *high) {
    *low = *high = 0;
    double period = effect.delay + effect.on;
    if (elapsed < 0 || effect.on <= 0 || period <= 0 || elapsed >= period * effect.cycles) return;
    if (fmod(elapsed, period) < effect.delay) return;
    *low = effect.low; *high = effect.high;
}

static int rumbleSelfTest(void) {
    // Independent fixtures, including Microsoft's 0..100 HID magnitude range.
    const uint8_t report[] = {3, 3, 0, 0, 100, 50, 20, 5, 0};
    RumbleEffect e; uint8_t out[8], low, high;
    if (!decodeRumble(3, report, sizeof(report), &e) || e.low != 255 || e.high != 127) return 1;
    encodeRumble(e.low, e.high, out);
    const uint8_t expected[] = {0, 8, 0, 255, 127, 0, 0, 0};
    if (memcmp(out, expected, 8)) return 1;
    if (!decodeRumble(3, report + 1, 8, &e)) return 1;
    rumbleAt(e, .02, &low, &high); if (low || high) return 1;
    rumbleAt(e, .10, &low, &high); if (low != 255 || high != 127) return 1;
    rumbleAt(e, .30, &low, &high); if (low || high) return 1;
    e.cycles = 2;
    rumbleAt(e, .27, &low, &high); if (low || high) return 1;
    rumbleAt(e, .35, &low, &high); if (low != 255 || high != 127) return 1;
    rumbleAt(e, .60, &low, &high); if (low || high) return 1;
    e.on = 0; rumbleAt(e, .10, &low, &high); if (low || high) return 1;
    uint8_t masked[] = {3, 1, 99, 99, 100, 255, 1, 0, 0};
    if (!decodeRumble(3, masked, 9, &e) || e.low || e.high != 255) return 1;
    masked[1] = 2;
    if (!decodeRumble(3, masked, 9, &e) || e.low != 255 || e.high) return 1;
    masked[1] = 0;
    if (!decodeRumble(3, masked, 9, &e) || e.low || e.high) return 1;
    if (decodeRumble(1, report, 9, &e) || decodeRumble(3, report, 7, &e) || decodeRumble(3, NULL, 8, &e)) return 1;
    masked[0] = 4; if (decodeRumble(3, masked, 9, &e)) return 1;
    masked[0] = 3; masked[1] = 0x80; if (decodeRumble(3, masked, 9, &e)) return 1;
    encodeRumble(0, 0, out);
    const uint8_t off[] = {0, 8, 0, 0, 0, 0, 0, 0};
    return memcmp(out, off, 8) != 0;
}
