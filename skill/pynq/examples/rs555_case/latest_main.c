/*
 * RS555 / PYNQ-Z2 integrated bare-metal test for Vitis 2026.1
 * Hardware: rs555_final.xsa built from AXI-IIC-repaired Vivado overlay.
 * Reuses verified xin1 XIic transaction sequence; NOT the old complete main.c.
 * DO NOT build this application against old xin1/design_1_wrapper.xsa.
 *
 * Motor PWM comes from physical BTN0..BTN3, NOT AXI duty/enable.
 * AXI GPIO ctrl: bit[9]=software ESTOP, bit10=fault override valid,
 *                bit11=fault override. Bits [8:0] except bit9 are reserved.
 * status0={rpm[15:0],vibration[15:0]} from software-fed ADXL GPIO
 * status1={soundA[15:0],soundB[15:0]}
 * status2={pcm_count_low16,adxl_devid[7:0],flags[7:0]}
 * audio: AXI DMA, simple S2MM, 4096 x 32-bit stereo samples @16 kHz
 * LCD: autonomously updated by FPGA logic.
 * I2C: AXI IIC (0x53), Vitis reads XYZ and feeds vibration/ID/ready to PL.
 *
 * SAFETY: Motor is disabled on FPGA reset until BTN3 START.
 *        BTN2 STOP, 'e' asserts software ESTOP, 'r' releases ESTOP.
 *        Hardware power disconnect is essential: REN/LEN tied high.
 */

#include "xparameters.h"
#include "xiic.h"
#include "xstatus.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "sleep.h"
#include <stdint.h>
#include "xuartps.h"
/* Named address macros are generated only when the platform is made from
 * the NEW exported XSA.  Never silently use XGPIO_0/1/2/3 indices: the AXI
 * address order is not guaranteed and could activate the motor by mistake.
 * For platform variants with a different macro spelling, look up the four
 * exact INSTANCE names in generated xparameters.h and edit the aliases here.
 */
#if defined(XPAR_AXI_GPIO_CTRL_BASEADDR)
# define RS_CTRL_BASE XPAR_AXI_GPIO_CTRL_BASEADDR
#elif defined(XPAR_AXI_GPIO_CTRL_0_BASEADDR)
# define RS_CTRL_BASE XPAR_AXI_GPIO_CTRL_0_BASEADDR
#else
# error "Missing AXI GPIO CTRL. Recreate Vitis platform using rs555_final.xsa; verify xparameters.h"
#endif

#if defined(XPAR_AXI_GPIO_STATUS0_BASEADDR)
# define RS_ST0_BASE XPAR_AXI_GPIO_STATUS0_BASEADDR
#elif defined(XPAR_AXI_GPIO_STATUS0_0_BASEADDR)
# define RS_ST0_BASE XPAR_AXI_GPIO_STATUS0_0_BASEADDR
#else
# error "Missing AXI GPIO STATUS0 in xparameters.h (new XSA required)"
#endif

#if defined(XPAR_AXI_GPIO_STATUS1_BASEADDR)
# define RS_ST1_BASE XPAR_AXI_GPIO_STATUS1_BASEADDR
#elif defined(XPAR_AXI_GPIO_STATUS1_0_BASEADDR)
# define RS_ST1_BASE XPAR_AXI_GPIO_STATUS1_0_BASEADDR
#else
# error "Missing AXI GPIO STATUS1 in xparameters.h (new XSA required)"
#endif

#if defined(XPAR_AXI_GPIO_STATUS2_BASEADDR)
# define RS_ST2_BASE XPAR_AXI_GPIO_STATUS2_BASEADDR
#elif defined(XPAR_AXI_GPIO_STATUS2_0_BASEADDR)
# define RS_ST2_BASE XPAR_AXI_GPIO_STATUS2_0_BASEADDR
#else
# error "Missing AXI GPIO STATUS2 in xparameters.h (new XSA required)"
#endif

#if defined(XPAR_AXI_DMA_AUDIO_BASEADDR)
# define RS_DMA_BASE XPAR_AXI_DMA_AUDIO_BASEADDR
#elif defined(XPAR_AXI_DMA_AUDIO_0_BASEADDR)
# define RS_DMA_BASE XPAR_AXI_DMA_AUDIO_0_BASEADDR
#else
# error "Missing AXI DMA AUDIO in xparameters.h (new XSA required)"
#endif

/* AXI IIC and the software-fed GPIO are ONLY in the repaired XSA.
 * These names refer to IP INSTANCE names in vivado/build_overlay.tcl. */
#if defined(XPAR_AXI_IIC_ADXL_BASEADDR)
# define RS_IIC_BASE XPAR_AXI_IIC_ADXL_BASEADDR
#elif defined(XPAR_AXI_IIC_ADXL_0_BASEADDR)
# define RS_IIC_BASE XPAR_AXI_IIC_ADXL_0_BASEADDR
#elif defined(XPAR_AXI_IIC_0_BASEADDR)
# define RS_IIC_BASE XPAR_AXI_IIC_0_BASEADDR
#else
# error "No AXI IIC ADXL base address. Regenerate Vitis platform from REPAIRED rs555_final.xsa."
#endif

#if defined(XPAR_AXI_GPIO_ADXL_SW_BASEADDR)
# define RS_ADXL_SW_BASE XPAR_AXI_GPIO_ADXL_SW_BASEADDR
#elif defined(XPAR_AXI_GPIO_ADXL_SW_0_BASEADDR)
# define RS_ADXL_SW_BASE XPAR_AXI_GPIO_ADXL_SW_0_BASEADDR
#else
# error "No ADXL software GPIO. Wrong XSA; use new AXI-IIC-repaired rs555_final.xsa."
#endif

#define ADXL_ADDR        0x53U
#define ADXL_DEVID_REG   0x00U
#define ADXL_BW_REG      0x2CU
#define ADXL_PWR_REG     0x2DU
#define ADXL_DATA_REG    0x32U

#define GPIO_DATA_OFFSET   0x0U
#define GPIO_TRI_OFFSET    0x4U
#define GPIO2_DATA_OFFSET  0x8U  /* AXI GPIO status2 channel 2 */
#define CTRL_ESTOP         (1U << 9)
#define CTRL_OVERRIDE      (1U << 10)
#define CTRL_FAULT         (1U << 11)

#define DMA_RX_CTRL        0x30U
#define DMA_RX_STATUS      0x34U
#define DMA_RX_DEST        0x48U
#define DMA_RX_LENGTH      0x58U
#define DMA_RESET          0x00000004U
#define DMA_RUN            0x00000001U
#define DMA_HALTED         0x00000001U
#define DMA_IDLE           0x00000002U
#define DMA_ERR_MASK       0x00000070U
#define DMA_IOC            0x00001000U

#define AUDIO_WORDS        4096U
#define AUDIO_BYTES        (AUDIO_WORDS * sizeof(uint32_t))
#define RPM_BUCKET_SIZE       200U
#define RPM_BUCKET_COUNT      25U

/* PWM-dependent speed monitoring: sample period is approximately 100 ms.
 * Fast response mode: 0.8 s PWM settle, 1.2 s fresh START settle,
 * 0.3 s vibration/sound abnormal confirmation, 0.3 s normal confirmation.
 * Speed drop remains ~0.5 s to avoid reacting to a single stale RPM value. */
#define PWM_BUCKET_COUNT      21U   /* 0%, 5%, ..., 100% */
#define RPM_DROP_PERCENT      15U   /* detect a >=15% sustained RPM loss at unchanged PWM */
#define RPM_RECOVER_PERCENT    8U   /* recover above 92% of RPM baseline */
#define RPM_DROP_CONFIRM      5U    /* ~0.5 s; tach RPM may refresh more slowly */
#define RPM_RECOVER_CONFIRM   5U
#define MOTOR_SETTLE_SAMPLES  8U    /* ~0.8 s after a PWM step */
#define MOTOR_START_SETTLE_SAMPLES 12U /* ~1.2 s after motor START */
#define PWM_BASE_MIN_SAMPLES  5U
#define SPEED_MIN_REF_RPM     200U
#define MIN_RUNNING_PWM      15U

#define VIB_MIN_MARGIN        30U
#define VIB_HIGH_PERCENT      100U
#define VIB_LOW_PERCENT       60U

#define ABNORMAL_CONFIRM_NUM  3U
#define NORMAL_CONFIRM_NUM    3U
#define SOUND_HIGH_PERCENT      60U
#define SOUND_LOW_PERCENT       40U

#define SOUND_ABNORMAL_CONFIRM_NUM  3U
#define SOUND_NORMAL_CONFIRM_NUM    5U
static uint32_t normal_vib_sum[RPM_BUCKET_COUNT];
static uint32_t normal_vib_count[RPM_BUCKET_COUNT];

static uint8_t vibration_state = 0U;
/*
 * 0 = 未知
 * 1 = 正常
 * 2 = 异常
 */

static unsigned abnormal_count = 0U;
static unsigned normal_count = 0U;
/* Static buffer in DDR; no special linker section needed on ordinary
 * standalone ps7_cortexa9_0 linker script. Align for cache maintenance. */
#if defined(__GNUC__)
static uint32_t audio_buffer[AUDIO_WORDS] __attribute__((aligned(64)));
#else
static uint32_t audio_buffer[AUDIO_WORDS];
#endif

/* Sensor state managed by Vitis; motor is never enabled by these functions. */
static XIic g_iic;
static int g_iic_started = 0;
static int g_sensor_ok = 0;
static int g_have_previous = 0;
static int16_t g_prev_x, g_prev_y, g_prev_z;
static int16_t g_x, g_y, g_z;
static uint16_t g_vibration;
static uint8_t g_devid;
static uint32_t normal_sound_sum[RPM_BUCKET_COUNT];
static uint32_t normal_sound_count[RPM_BUCKET_COUNT];

static unsigned sound_abnormal_count = 0U;
static unsigned sound_normal_count = 0U;
static unsigned both_abnormal_count = 0U;
/* Normal RPM versus actual hardware PWM. Stored only by explicit 'n' calibration. */
static uint32_t normal_rpm_sum[PWM_BUCKET_COUNT];
static uint32_t normal_rpm_count[PWM_BUCKET_COUNT];
static unsigned g_last_pwm = 255U;
static unsigned g_last_running = 0U;
static unsigned g_motor_settle = MOTOR_SETTLE_SAMPLES;
static unsigned g_rpm_drop_count = 0U;
static unsigned g_rpm_recover_count = 0U;
static uint8_t g_speed_fault = 0U; /* latched with hysteresis */
static int g_rpm_ref_valid = 0;
static unsigned g_rpm_ref = 0U;
/* Keep AXI GPIO output state in software; GPIO DATA readback is not an
 * authoritative software latch on every hardware configuration. */
static uint32_t g_ctrl_shadow = CTRL_ESTOP;
static unsigned g_valid_accel_samples = 0U;
static unsigned get_rpm_bucket(unsigned rpm)
{
    unsigned bucket = rpm / RPM_BUCKET_SIZE;

    if (bucket >= RPM_BUCKET_COUNT)
        bucket = RPM_BUCKET_COUNT - 1U;

    return bucket;
}
static inline uint32_t rd(uint32_t base, uint32_t offset)
{
    return Xil_In32((UINTPTR)base + offset);
}
static inline void wr(uint32_t base, uint32_t offset, uint32_t val)
{
    Xil_Out32((UINTPTR)base + offset, val);
}

/* status2 channel-2 is a read-only view of the FPGA motor controller. */
static uint32_t motor_status_read(void)
{
    return rd(RS_ST2_BASE, GPIO2_DATA_OFFSET);
}
static unsigned motor_pwm_percent(void)
{
    return (unsigned)(motor_status_read() & 0xFFU);
}
static unsigned motor_is_running(void)
{
    return (unsigned)((motor_status_read() >> 8) & 1U);
}
static int pwm_bucket(unsigned pwm)
{
    if (pwm > 100U || (pwm % 5U) != 0U) return -1;
    return (int)(pwm / 5U);
}
static int get_normal_rpm_at_pwm(unsigned pwm, unsigned *rpm_baseline)
{
    int b = pwm_bucket(pwm);
    if (rpm_baseline == 0 || b < 0 ||
        normal_rpm_count[b] < PWM_BASE_MIN_SAMPLES)
        return -1;
    *rpm_baseline = normal_rpm_sum[b] / normal_rpm_count[b];
    return (*rpm_baseline >= SPEED_MIN_REF_RPM) ? 0 : -1;
}

/* A PWM step or a fresh START requires settling before speed comparison.
 * Call exactly once per 100-ms monitor/calibration loop iteration. */
static void motor_track_changes(unsigned pwm, unsigned running)
{
    if (pwm != g_last_pwm || running != g_last_running) {
        unsigned was_running = g_last_running;
        g_last_pwm = pwm;
        g_last_running = running;
        /* A fresh START needs longer acceleration time than a 5% PWM step. */
        g_motor_settle = (running && !was_running) ?
            MOTOR_START_SETTLE_SAMPLES : MOTOR_SETTLE_SAMPLES;
        g_rpm_drop_count = 0U;
        g_rpm_recover_count = 0U;
        g_speed_fault = 0U;
    } else if (g_motor_settle > 0U) {
        --g_motor_settle;
    }
}

static uint32_t lcd_state_bits(void)
{
    if (vibration_state == 1U)
        return CTRL_OVERRIDE;               /* confirmed NORMAL */
    if (vibration_state == 2U || vibration_state == 3U)
        return CTRL_OVERRIDE | CTRL_FAULT;  /* fault or SENSOR_ERROR */
    return 0U;                              /* not calibrated / unknown */
}
static void ctrl_publish(void)
{
    wr(RS_CTRL_BASE, GPIO_DATA_OFFSET,
       (g_ctrl_shadow & CTRL_ESTOP) | lcd_state_bits());
}
static void motor_stop(void)
{
    /* Software ESTOP; BTN3 cannot restart until released. */
    g_ctrl_shadow |= CTRL_ESTOP;
    ctrl_publish();
}
static void lcd_publish_state(void)
{
    ctrl_publish();
}
static void motor_release_estop(void)
{
    g_ctrl_shadow &= ~CTRL_ESTOP;
    ctrl_publish();
}
static void motor_init(void)
{
    /* First force ESTOP while configuring AXI GPIO, then release it.
     * The FPGA motor controller itself starts in STOPPED state on reset. */
    motor_stop();
    wr(RS_CTRL_BASE, GPIO_TRI_OFFSET, 0U);
    motor_release_estop();
}
/* AXI GPIO channel 1, [24]=ready, [23:16]=DEVID, [15:0]=vibration. */
static void sensor_publish(void)
{
    uint32_t word = ((uint32_t)(g_sensor_ok ? 1U : 0U) << 24)
                  | ((uint32_t)g_devid << 16)
                  | (uint32_t)g_vibration;
    wr(RS_ADXL_SW_BASE, GPIO_DATA_OFFSET, word);
}

/* A missing sensor is NOT a valid zero-vibration reading. */
static void sensor_mark_error(void)
{
    g_sensor_ok = 0;
    g_have_previous = 0;
    g_valid_accel_samples = 0U;
    g_vibration = 0;
    g_x = g_y = g_z = 0;
    vibration_state = 3U; /* distinguish SENSOR_ERROR from motor fault */
    abnormal_count = normal_count = 0U;
    sound_abnormal_count = sound_normal_count = both_abnormal_count = 0U;
    sensor_publish();
    lcd_publish_state();
}

static int adxl_write(uint8_t reg, uint8_t value)
{
    uint8_t packet[2];
    packet[0] = reg;
    packet[1] = value;
    return XIic_Send(g_iic.BaseAddress, ADXL_ADDR, packet, 2, XIIC_STOP) == 2 ? 0 : -1;
}

static int adxl_read(uint8_t reg, uint8_t *data, int size)
{
    uint8_t pointer = reg;
    if (XIic_Send(g_iic.BaseAddress, ADXL_ADDR, &pointer, 1, XIIC_REPEATED_START) != 1)
        return -1;
    if (XIic_Recv(g_iic.BaseAddress, ADXL_ADDR, data, size, XIIC_STOP) != size)
        return -1;
    return 0;
}

/* Copy of yesterday's verified XIic transaction pattern, now attached to new AXI IIC. */
static int sensor_init(void)
{
    int result;
    uint8_t id = 0U, fmt = 0U, bw = 0U, pwr = 0U;

    g_devid = 0U;
    sensor_mark_error();
    if (!g_iic_started) {
        result = XIic_Initialize(&g_iic, RS_IIC_BASE);
        if (result != XST_SUCCESS) {
            xil_printf("AXI IIC initialize failed: %d\r\n", result);
            return -1;
        }
        result = XIic_Start(&g_iic);
        if (result != XST_SUCCESS) {
            xil_printf("AXI IIC start failed: %d\r\n", result);
            return -1;
        }
        g_iic_started = 1;
    }
    if (adxl_read(ADXL_DEVID_REG, &id, 1) != 0) {
        xil_printf("ADXL345 DEVID read failed; check CS, SDA/SCL, 3.3V and pull-ups\r\n");
        return -1;
    }
    g_devid = id;
    sensor_publish();
    if (id != 0xE5U) {
        xil_printf("ADXL345 unexpected ID 0x%02X, expected E5\r\n", (unsigned)id);
        return -1;
    }
    /* Enter standby before changing format and ODR; start measurement last. */
    if (adxl_write(ADXL_PWR_REG, 0x00U) != 0 ||
        adxl_write(0x31U, 0x08U) != 0 ||
        adxl_write(ADXL_BW_REG, 0x0AU) != 0 ||
        adxl_write(ADXL_PWR_REG, 0x08U) != 0) {
        xil_printf("ADXL345 register write FAILED\r\n");
        return -1;
    }
    /* Write ACK does not prove the device accepted its configuration. */
    if (adxl_read(0x31U, &fmt, 1) != 0 ||
        adxl_read(ADXL_BW_REG, &bw, 1) != 0 ||
        adxl_read(ADXL_PWR_REG, &pwr, 1) != 0) {
        xil_printf("ADXL345 configuration readback FAILED\r\n");
        return -1;
    }
    xil_printf("ADXL cfg: DATA_FORMAT=0x%02X BW_RATE=0x%02X POWER_CTL=0x%02X\r\n",
               (unsigned)fmt, (unsigned)bw, (unsigned)pwr);
    if (fmt != 0x08U || bw != 0x0AU || (pwr & 0x08U) == 0U) {
        xil_printf("ADXL345 configuration mismatch: SENSOR_ERROR\r\n");
        return -1;
    }
    /* Allow a fresh measurement before the first sample. */
    usleep(20000U);
    g_sensor_ok = 1;
    vibration_state = 0U;
    sensor_publish();
    lcd_publish_state();
    xil_printf("ADXL345 DEVID=0xE5; register readback OK; measurement enabled\r\n");
    return 0;
}

static uint32_t abs_delta(int16_t a, int16_t b)
{
    int32_t d = (int32_t)a - (int32_t)b;
    return (uint32_t)(d < 0 ? -d : d);
}

/* Called before each status report; a slow/stationary sensor may report Vib=0. */
static int sensor_sample(void)
{
    uint8_t b[6];
    uint32_t delta;
    if (!g_sensor_ok) return -1;
    if (adxl_read(ADXL_DATA_REG, b, 6) != 0) {
        xil_printf("ADXL345 XYZ read failed; disabling ready until retry [i]\r\n");
        sensor_mark_error();
        return -1;
    }
    g_x = (int16_t)(((uint16_t)b[1] << 8) | b[0]);
    g_y = (int16_t)(((uint16_t)b[3] << 8) | b[2]);
    g_z = (int16_t)(((uint16_t)b[5] << 8) | b[4]);
    if (g_have_previous) {
        delta = abs_delta(g_x, g_prev_x) +
                abs_delta(g_y, g_prev_y) + abs_delta(g_z, g_prev_z);
        g_vibration = (uint16_t)(delta > 65535U ? 65535U : delta);
    } else {
        g_vibration = 0;
        g_have_previous = 1;
    }
    g_prev_x = g_x;
    g_prev_y = g_y;
    g_prev_z = g_z;
    if (g_valid_accel_samples < 1000000U) ++g_valid_accel_samples;
    sensor_publish();
    return 0;
}
static void record_normal_baseline(void)
{
    uint32_t st0;
    uint32_t st1;
    unsigned rpm;
    unsigned vibration;
    unsigned sound_a;
    unsigned sound_b;
    unsigned sound_level;
    unsigned bucket;
    unsigned pwm;
    unsigned running;
    int pb;

    st0 = rd(RS_ST0_BASE, GPIO_DATA_OFFSET);
    st1 = rd(RS_ST1_BASE, GPIO_DATA_OFFSET);

    rpm = (unsigned)((st0 >> 16) & 0xFFFFU);
    vibration = (unsigned)(st0 & 0xFFFFU);

    sound_a = (unsigned)((st1 >> 16) & 0xFFFFU);
    sound_b = (unsigned)(st1 & 0xFFFFU);
    sound_level = sound_a > sound_b ? sound_a : sound_b;

    /* Never train a baseline from missing ADXL data or the initial zero delta. */
    pwm = motor_pwm_percent();
    running = motor_is_running();
    /* No auto-training from missing sensor, stopped motor or PWM transients. */
    if (rpm < 100U || !running || !g_sensor_ok ||
        g_valid_accel_samples < 2U || g_motor_settle > 0U)
        return;

    bucket = get_rpm_bucket(rpm);

    normal_vib_sum[bucket] += vibration;
    normal_vib_count[bucket]++;

    normal_sound_sum[bucket] += sound_level;
    normal_sound_count[bucket]++;

    /* Speed baseline is keyed to the ACTUAL FPGA button-selected PWM. */
    pb = pwm_bucket(pwm);
    if (pb >= 0 && pwm >= MIN_RUNNING_PWM) {
        normal_rpm_sum[pb] += rpm;
        normal_rpm_count[pb]++;
        if (normal_rpm_count[pb] > 1000U) {
            normal_rpm_sum[pb] /= 2U;
            normal_rpm_count[pb] /= 2U;
        }
    }

    if (normal_vib_count[bucket] > 1000U) {
        normal_vib_sum[bucket] /= 2U;
        normal_vib_count[bucket] /= 2U;
    }

    if (normal_sound_count[bucket] > 1000U) {
        normal_sound_sum[bucket] /= 2U;
        normal_sound_count[bucket] /= 2U;
    }
}

static int find_nearest_calibrated_bucket(unsigned rpm)
{
    unsigned i;
    unsigned current = get_rpm_bucket(rpm);
    unsigned best_distance = ~0U;
    int best_bucket = -1;

    if (normal_vib_count[current] >= 5U &&
        normal_sound_count[current] >= 5U)
        return (int)current;

    for (i = 0U; i < RPM_BUCKET_COUNT; ++i) {
        unsigned low;
        unsigned high;
        unsigned distance;

        if (normal_vib_count[i] < 5U || normal_sound_count[i] < 5U)
            continue;

        low = i * RPM_BUCKET_SIZE;
        if (i == RPM_BUCKET_COUNT - 1U)
            high = ~0U; /* final bucket includes every higher RPM */
        else
            high = (i + 1U) * RPM_BUCKET_SIZE - 1U;

        if (rpm < low)
            distance = low - rpm;
        else if (rpm > high)
            distance = rpm - high;
        else
            distance = 0U;

        /* Strict < keeps the lower-speed bucket when distances tie. */
        if (best_bucket < 0 || distance < best_distance) {
            best_distance = distance;
            best_bucket = (int)i;
        }
    }
    return best_bucket;
}

static int get_normal_baseline(unsigned rpm, unsigned *baseline)
{
    int bucket = find_nearest_calibrated_bucket(rpm);

    if (bucket < 0 || baseline == 0)
        return -1;

    *baseline = normal_vib_sum[bucket] / normal_vib_count[bucket];
    return 0;
}

static int get_normal_sound_baseline(unsigned rpm, unsigned *baseline)
{
    int bucket = find_nearest_calibrated_bucket(rpm);

    if (bucket < 0 || baseline == 0)
        return -1;

    *baseline = normal_sound_sum[bucket] / normal_sound_count[bucket];
    return 0;
}
/* Combined speed + vibration + sound anomaly state.
 * SPEED_FAULT when RPM persistently drops at unchanged PWM.
 * Vibration/sound still use the nearest valid *RPM* calibration bucket.
 * No speed reference at current PWM => speed test is UNKNOWN, not NORMAL.
 */
static int update_vibration_state(void)
{
    uint32_t st0 = rd(RS_ST0_BASE, GPIO_DATA_OFFSET);
    uint32_t st1 = rd(RS_ST1_BASE, GPIO_DATA_OFFSET);
    unsigned rpm = (unsigned)((st0 >> 16) & 0xFFFFU);
    unsigned vib = (unsigned)(st0 & 0xFFFFU);
    unsigned snd_a = (unsigned)((st1 >> 16) & 0xFFFFU);
    unsigned snd_b = (unsigned)(st1 & 0xFFFFU);
    unsigned sound = snd_a > snd_b ? snd_a : snd_b;
    uint32_t motor = motor_status_read();
    unsigned pwm = (unsigned)(motor & 0xFFU);
    unsigned running = (unsigned)((motor >> 8) & 1U);
    unsigned vib_base = 0U, snd_base = 0U, rpm_base = 0U;
    int have_vs, have_speed;
    int vib_hi = 0, sound_hi = 0, vib_lo = 0, sound_lo = 0;
    unsigned vib_hi_margin, vib_lo_margin, snd_hi_margin, snd_lo_margin;
    int any_fault, all_normal, have_evidence;

    motor_track_changes(pwm, running);
    g_rpm_ref_valid = 0;
    g_rpm_ref = 0U;
    if (!g_sensor_ok) {
        sensor_mark_error();
        return -1;
    }
    if (g_valid_accel_samples < 2U || !running || pwm < MIN_RUNNING_PWM) {
        vibration_state = 0U;
        abnormal_count = sound_abnormal_count = both_abnormal_count = 0U;
        normal_count = 0U;
        g_rpm_drop_count = g_rpm_recover_count = 0U;
        g_speed_fault = 0U;
        lcd_publish_state();
        return 0;
    }
    /* Current PWM must have its OWN normal-RPM baseline: no nearest-PWM
     * approximation for overload detection, which would create false alarms. */
    have_speed = (get_normal_rpm_at_pwm(pwm, &rpm_base) == 0);
    if (have_speed) {
        g_rpm_ref_valid = 1;
        g_rpm_ref = rpm_base;
    }
    if (have_speed && g_motor_settle == 0U) {
        /* Compare ratios without unsigned subtract/underflow. */
        if ((uint64_t)rpm * 100U <=
            (uint64_t)rpm_base * (100U - RPM_DROP_PERCENT)) {
            if (g_rpm_drop_count < RPM_DROP_CONFIRM) ++g_rpm_drop_count;
            g_rpm_recover_count = 0U;
            if (g_rpm_drop_count >= RPM_DROP_CONFIRM) g_speed_fault = 1U;
        } else if ((uint64_t)rpm * 100U >=
                   (uint64_t)rpm_base * (100U - RPM_RECOVER_PERCENT)) {
            if (g_rpm_recover_count < RPM_RECOVER_CONFIRM) ++g_rpm_recover_count;
            g_rpm_drop_count = 0U;
            if (g_rpm_recover_count >= RPM_RECOVER_CONFIRM) g_speed_fault = 0U;
        } else {
            g_rpm_drop_count = 0U;
            g_rpm_recover_count = 0U;
        }
    }

    /* If rpm becomes zero, a persistent speed drop is still detectable. */
    have_vs = rpm >= 100U &&
              get_normal_baseline(rpm, &vib_base) == 0 &&
              get_normal_sound_baseline(rpm, &snd_base) == 0;
    if (have_vs && g_motor_settle == 0U) {
        vib_hi_margin = vib_base * VIB_HIGH_PERCENT / 100U;
        vib_lo_margin = vib_base * VIB_LOW_PERCENT / 100U;
        snd_hi_margin = snd_base * SOUND_HIGH_PERCENT / 100U;
        snd_lo_margin = snd_base * SOUND_LOW_PERCENT / 100U;
        if (vib_hi_margin < VIB_MIN_MARGIN) vib_hi_margin = VIB_MIN_MARGIN;
        if (vib_lo_margin < VIB_MIN_MARGIN) vib_lo_margin = VIB_MIN_MARGIN;
        if (snd_hi_margin < VIB_MIN_MARGIN) snd_hi_margin = VIB_MIN_MARGIN;
        if (snd_lo_margin < VIB_MIN_MARGIN) snd_lo_margin = VIB_MIN_MARGIN;
        vib_hi = vib >= vib_base + vib_hi_margin;
        sound_hi = sound >= snd_base + snd_hi_margin;
        vib_lo = vib <= vib_base + vib_lo_margin;
        sound_lo = sound <= snd_base + snd_lo_margin;
        abnormal_count = vib_hi ? abnormal_count + 1U : 0U;
        sound_abnormal_count = sound_hi ? sound_abnormal_count + 1U : 0U;
        both_abnormal_count = (vib_hi && sound_hi) ? both_abnormal_count + 1U : 0U;
    } else {
        abnormal_count = sound_abnormal_count = both_abnormal_count = 0U;
    }

    /* Unknown baseline is not proof of normality. During settling,
     * preserve neither stale alerts nor a misleading NORMAL classification. */
    if (g_motor_settle > 0U) {
        vibration_state = 0U;
        normal_count = 0U;
        lcd_publish_state();
        return 0;
    }
    /* Only label the fully checked system NORMAL if both reference types exist.
     * A missing PWM/RPM baseline means overload cannot be assessed.
     * Keep vibration/sound alarms active even when speed calibration is absent. */
    have_evidence = have_vs && have_speed;
    any_fault = g_speed_fault ||
                (have_vs && (both_abnormal_count >= 2U ||
                             abnormal_count >= ABNORMAL_CONFIRM_NUM ||
                             sound_abnormal_count >= SOUND_ABNORMAL_CONFIRM_NUM));

    /* For entry into NORMAL, require 3 consecutive samples that do not cross
     * the HIGH alarm thresholds. Requiring the lower recovery thresholds even
     * when no alarm has occurred kept a healthy motor UNKNOWN for too long.
     * After an alarm, keep the stricter LOW recovery thresholds (hysteresis). */
    all_normal = have_evidence && !g_speed_fault &&
                 ((vibration_state == 2U) ?
                      (vib_lo && sound_lo) : (!vib_hi && !sound_hi));
    if (any_fault) {
        vibration_state = 2U;
        normal_count = 0U;
    } else if (all_normal) {
        if (normal_count < NORMAL_CONFIRM_NUM) ++normal_count;
        if (normal_count >= NORMAL_CONFIRM_NUM) vibration_state = 1U;
    } else {
        normal_count = 0U;
        /* No full reference, no assurance of normal operation. */
        if (!have_evidence) vibration_state = 0U;
    }
    lcd_publish_state();
    return 0;
}
static const char *vibration_state_text(void)
{
    /* Distinguish an incomplete test from a true fault or verified NORMAL. */
    if (vibration_state == 3U) return "SENSOR_ERROR";
    if (vibration_state == 2U) return "ABNORMAL";
    if (!g_last_running) return "STOPPED";
    if (g_motor_settle != 0U) return "SETTLING";
    if (!g_rpm_ref_valid) return "NO_PWM_BASE";
    if (vibration_state == 1U) return "NORMAL";
    return "CHECKING";
}
static void show_status(void)
{
    (void)sensor_sample();
    uint32_t s0 = rd(RS_ST0_BASE, GPIO_DATA_OFFSET);
    uint32_t s1 = rd(RS_ST1_BASE, GPIO_DATA_OFFSET);
    uint32_t s2 = rd(RS_ST2_BASE, GPIO_DATA_OFFSET);
    uint32_t flags = s2 & 0xFFU;
    unsigned int rpm = (unsigned int)((s0 >> 16) & 0xFFFFU);
    unsigned int vibration = (unsigned int)(s0 & 0xFFFFU);
    unsigned int sound_a = (unsigned int)((s1 >> 16) & 0xFFFFU);
    unsigned int sound_b = (unsigned int)(s1 & 0xFFFFU);
    unsigned int devid = (unsigned int)((s2 >> 8) & 0xFFU);
    unsigned int pcm16 = (unsigned int)((s2 >> 16) & 0xFFFFU);

    xil_printf("\r\nRPM=%u  Vib=%u  SoundA=%u  SoundB=%u\r\n",
               rpm, vibration, sound_a, sound_b);
    xil_printf("ADXL345 DEVID=0x%02X (%s), ready=%u\r\n", devid,
               devid == 0xE5U ? "OK" : "CHECK", (unsigned)(flags & 1U));
    xil_printf("TachSeen=%u  MotorOn=%u  FaultDisplay=%u  LCDFrame=%u  DMICAlive=%u\r\n",
               (unsigned)((flags >> 1) & 1U),
               (unsigned)((flags >> 2) & 1U),
               (unsigned)((flags >> 3) & 1U),
               (unsigned)((flags >> 4) & 1U),
               (unsigned)((flags >> 5) & 1U));
    {
        uint32_t motor = motor_status_read();
        unsigned pwm = (unsigned)(motor & 0xFFU);
        unsigned rpm_ref = 0U;
        xil_printf("PWM=%u%% MotorRUN=%u ESTOP=%u NormalRPM=%s",
                   pwm, (unsigned)((motor >> 8) & 1U),
                   (unsigned)((motor >> 9) & 1U),
                   get_normal_rpm_at_pwm(pwm, &rpm_ref) == 0 ? "YES" : "NO");
        if (get_normal_rpm_at_pwm(pwm, &rpm_ref) == 0)
            xil_printf("(%u)", rpm_ref);
        xil_printf("\r\n");
    }
    xil_printf("PCM_count_low16=%u  flags=0x%02X\r\n", pcm16, (unsigned)flags);
    xil_printf("XYZ raw: X=%d Y=%d Z=%d; Sensor=%s (Vib=inter-sample delta)\r\n",
               (int)g_x, (int)g_y, (int)g_z,
               g_sensor_ok ? "READY" : "SENSOR_ERROR");
}

static int dma_reset_rx(void)
{
    unsigned i;
    wr(RS_DMA_BASE, DMA_RX_CTRL, DMA_RESET);
    for (i=0; i<5000U; ++i) {
        if ((rd(RS_DMA_BASE, DMA_RX_CTRL) & DMA_RESET) == 0U)
            return 0;
        usleep(100U);
    }
    xil_printf("DMA reset timed out\r\n");
    return -1;
}

static void monitor_until_key(void)
{
    unsigned tick = 0U;
    xil_printf("LIVE: 100ms sampling / approx. 500ms print; any non-CR/LF key exits.\r\n");
    xil_printf("'e' during LIVE also asserts software ESTOP.\r\n");
    while (1) {
        if (XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
            char key = (char)XUartPs_RecvByte(STDIN_BASEADDRESS);
            if (key != '\r' && key != '\n') {
                if (key == 'e' || key == 'E') motor_stop();
                xil_printf("\r\nLIVE stopped.\r\n");
                return;
            }
        }
        (void)sensor_sample();
        (void)update_vibration_state();
        if ((tick % 5U) == 0U) {
            uint32_t a = rd(RS_ST0_BASE, GPIO_DATA_OFFSET);
            uint32_t b = rd(RS_ST1_BASE, GPIO_DATA_OFFSET);
            uint32_t m = motor_status_read();
            unsigned rpm = (unsigned)((a >> 16) & 0xFFFFU);
            unsigned vib = (unsigned)(a & 0xFFFFU);
            unsigned pwm = (unsigned)(m & 0xFFU);
            unsigned rpm_ref = 0U, vib_ref = 0U, snd_ref = 0U;
            int have_speed = get_normal_rpm_at_pwm(pwm, &rpm_ref) == 0;
            int ref_bucket = find_nearest_calibrated_bucket(rpm);
            (void)get_normal_baseline(rpm, &vib_ref);
            (void)get_normal_sound_baseline(rpm, &snd_ref);
            xil_printf("t=%ums PWM=%u%% RUN=%u RPM=%u RPMBase=",
                       tick * 100U, pwm, (unsigned)((m >> 8) & 1U), rpm);
            if (have_speed) xil_printf("%u", rpm_ref);
            else xil_printf("NONE");
            xil_printf(" Vib=%u VibBase=%u SoundA=%u SoundB=%u SoundBase=%u",
                       vib, vib_ref, (unsigned)((b >> 16) & 0xFFFFU),
                       (unsigned)(b & 0xFFFFU), snd_ref);
            if (ref_bucket >= 0)
                xil_printf(" RefRPM=%u%s", (unsigned)ref_bucket * RPM_BUCKET_SIZE,
                           ref_bucket == (int)RPM_BUCKET_COUNT-1 ? "+" : "-bucket");
            else xil_printf(" RefRPM=NONE");
            xil_printf(" State=%s SpeedFault=%u Settle=%u Sensor=%s XYZ=(%d,%d,%d)",
                       vibration_state_text(), (unsigned)g_speed_fault,
                       g_motor_settle, g_sensor_ok ? "OK" : "ERROR",
                       (int)g_x, (int)g_y, (int)g_z);
            if (have_speed && rpm_ref != 0U) {
                /* A positive percentage means the shaft is slower than normal. */
                unsigned drop_pct = (rpm < rpm_ref) ?
                    (unsigned)(((uint64_t)(rpm_ref - rpm) * 100U) / rpm_ref) : 0U;
                xil_printf(" RPMDrop=%u%%", drop_pct);
            }
            xil_printf("\r\n");
        }
        ++tick;
        usleep(100000U);
    }
}
static void audio_test(void)
{
    unsigned i;
    uint32_t status;
    uint32_t peak_a=0U, peak_b=0U;
    uint64_t sum_a=0U, sum_b=0U;
    UINTPTR bufaddr = (UINTPTR)audio_buffer;

    xil_printf("Capturing %u stereo words (about 256ms)...\r\n", AUDIO_WORDS);
    if (dma_reset_rx() != 0) return;

    /* DMA receives words into cacheable DDR; maintain CPU data cache. */
    Xil_DCacheFlushRange(bufaddr, AUDIO_BYTES);
    Xil_DCacheInvalidateRange(bufaddr, AUDIO_BYTES);
    wr(RS_DMA_BASE, DMA_RX_STATUS, DMA_IOC | DMA_ERR_MASK); /* clear stale W1C bits */
    wr(RS_DMA_BASE, DMA_RX_CTRL, DMA_RUN);
    for (i=0; i<1000U; ++i) {
        status=rd(RS_DMA_BASE,DMA_RX_STATUS);
        if ((status & DMA_HALTED)==0U) break;
        usleep(100U);
    }
    if (i==1000U) {
        xil_printf("DMA channel did not start\r\n");
        (void)dma_reset_rx(); return;
    }

    wr(RS_DMA_BASE, DMA_RX_DEST, (uint32_t)bufaddr);
    wr(RS_DMA_BASE, DMA_RX_LENGTH, (uint32_t)AUDIO_BYTES);
    for (i=0; i<2000U; ++i) {
        status=rd(RS_DMA_BASE, DMA_RX_STATUS);
        if (status & DMA_ERR_MASK) {
            xil_printf("DMA receive ERROR: status=0x%08X\r\n", (unsigned)status);
            (void)dma_reset_rx(); return;
        }
        if ((status & DMA_IDLE) || (status & DMA_IOC)) break;
        usleep(1000U);
    }
    if (i==2000U) {
        xil_printf("DMA timeout; status=0x%08X\r\n", (unsigned)status);
        (void)dma_reset_rx(); return;
    }
    Xil_DCacheInvalidateRange(bufaddr, AUDIO_BYTES);

    for (i=0; i<AUDIO_WORDS; ++i) {
        uint32_t word = audio_buffer[i];
        int32_t a=(int16_t)(word & 0xFFFFU);
        int32_t b=(int16_t)((word >> 16) & 0xFFFFU);
        uint32_t aa=(uint32_t)(a<0?-a:a);
        uint32_t ab=(uint32_t)(b<0?-b:b);
        if (aa>peak_a) peak_a=aa;
        if (ab>peak_b) peak_b=ab;
        sum_a += aa;
        sum_b += ab;
    }
    xil_printf("Audio capture OK: peak A=%u, peak B=%u, mean-abs A=%u, B=%u\r\n",
               (unsigned)peak_a,(unsigned)peak_b,
               (unsigned)(sum_a/AUDIO_WORDS), (unsigned)(sum_b/AUDIO_WORDS));
    xil_printf("First samples [A,B]: ");
    for(i=0;i<6U;i++) {
        uint32_t w=audio_buffer[i];
        xil_printf("(%d,%d) ", (int16_t)w, (int16_t)(w>>16));
    }
    xil_printf("\r\n");
}

static void motor_button_help(void)
{
    xil_printf("Motor control is from onboard buttons ONLY:\r\n");
    xil_printf("BTN0 -5%%, BTN1 +5%%, BTN2 STOP, BTN3 START.\r\n");
    xil_printf("Default 50%%, stopped at FPGA reset; 25 kHz PWM on JB1/W14.\r\n");
    xil_printf("'e' = software ESTOP; 'r' = release ESTOP, then press BTN3.\r\n");
    xil_printf("Software ESTOP=%u\r\n",
               (unsigned)((g_ctrl_shadow & CTRL_ESTOP) != 0U));
    show_status();
}

int main(void)
{
    char cmd;
    motor_init(); /* first operation after entry: force motor off */
    xil_printf("\r\n================ RS555 PYNQ-Z2 ================\r\n");
    xil_printf("Vitis 2026.1 standalone / AXI IIC FIXED rs555_final.xsa\r\n");
    xil_printf("CTRL=0x%08X ST0=0x%08X ST1=0x%08X ST2=0x%08X DMA=0x%08X\r\n",
               (unsigned)RS_CTRL_BASE,(unsigned)RS_ST0_BASE,
               (unsigned)RS_ST1_BASE,(unsigned)RS_ST2_BASE,(unsigned)RS_DMA_BASE);
    xil_printf("AXI IIC=0x%08X ADXL software GPIO=0x%08X\r\n",
               (unsigned)RS_IIC_BASE,(unsigned)RS_ADXL_SW_BASE);
    xil_printf("ADXL345 uses AXI IIC. PWM/RPM status is AXI GPIO STATUS2 channel 2.\r\n");
    xil_printf("LCD is updated autonomously in FPGA. Motor defaults OFF.\r\n");
    xil_printf("Motor buttons: BTN0 -5%%, BTN1 +5%%, BTN2 STOP, BTN3 START.\r\n");
    /* Release output bit lane, then initialize the sensor without turning on the motor. */
    wr(RS_ADXL_SW_BASE, GPIO_DATA_OFFSET, 0U);
    wr(RS_ADXL_SW_BASE, GPIO_TRI_OFFSET, 0U);
    (void)sensor_init();
    show_status();
    while(1) {
        xil_printf("\r\n[s] live [p] status [c] live(alias) [n] calibration [i] I2C retry [a] audio [m] buttons [e] ESTOP [r] release [q] idle > ");
        cmd=inbyte();
        /* Discard terminal Enter by itself, not a command. */
        if (cmd == '\r' || cmd == '\n') continue;
        xil_printf("%c\r\n",cmd);
        if (cmd=='s' || cmd=='S' || cmd=='c' || cmd=='C') monitor_until_key();
        else if (cmd=='p' || cmd=='P') show_status();
        else if (cmd=='i' || cmd=='I') { (void)sensor_init(); show_status(); }
        else if (cmd=='a' || cmd=='A') audio_test();
        else if (cmd=='m' || cmd=='M') motor_button_help();
        else if (cmd=='e' || cmd=='E') {
            motor_stop(); xil_printf("Software ESTOP asserted. BTN3 cannot start motor.\r\n");
        }
        else if (cmd=='r' || cmd=='R') {
            motor_release_estop();
            xil_printf("Software ESTOP released. Press BTN3 to START.\r\n");
        }
        else if (cmd=='q' || cmd=='Q') {
            motor_stop(); xil_printf("Motor OFF. Program idle (press reset to restart).\r\n");
            while(1) usleep(1000000U);
        }
        else if (cmd=='n' || cmd=='N') {
            unsigned i;

            if (!g_sensor_ok) {
                xil_printf("Cannot calibrate: ADXL345 SENSOR_ERROR. Press i to retry.\r\n");
                continue;
            }
            xil_printf("Recording normal vibration + sound + PWM/RPM baselines.\r\n");
            xil_printf("Keep motor operating normally; adjust speed if needed.\r\n");
            xil_printf("Press 'a' to stop calibration.\r\n");

            for (i = 0U; ; ++i) {
                if (XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
                    char key = (char)XUartPs_RecvByte(STDIN_BASEADDRESS);

                    if (key == 'a' || key == 'A') {
                        xil_printf("\r\nNormal calibration stopped.\r\n");
                        break;
                    }
                }

                if (sensor_sample() != 0) {
                    xil_printf("Calibration aborted: ADXL345 SENSOR_ERROR. Press i to retry.\r\n");
                    break;
                }
                {
                    uint32_t m = motor_status_read();
                    motor_track_changes((unsigned)(m & 0xFFU),
                                        (unsigned)((m >> 8) & 1U));
                }
                record_normal_baseline();

                if (i % 5U == 0U) {
                uint32_t st0 = rd(RS_ST0_BASE, GPIO_DATA_OFFSET);
                uint32_t st1 = rd(RS_ST1_BASE, GPIO_DATA_OFFSET);

                unsigned rpm = (unsigned)((st0 >> 16) & 0xFFFFU);
                unsigned vibration = (unsigned)(st0 & 0xFFFFU);
                unsigned sound_a = (unsigned)((st1 >> 16) & 0xFFFFU);
                unsigned sound_b = (unsigned)(st1 & 0xFFFFU);
                unsigned sound_level = sound_a > sound_b ? sound_a : sound_b;
                unsigned vib_baseline = 0U;
                unsigned sound_baseline = 0U;
                unsigned rpm_pwm_baseline = 0U;
                (void)get_normal_rpm_at_pwm(motor_pwm_percent(), &rpm_pwm_baseline);

                (void)get_normal_baseline(rpm, &vib_baseline);
                (void)get_normal_sound_baseline(rpm, &sound_baseline);

                xil_printf(
                    "Calibrating: RPM=%u Vib=%u VibBase=%u "
                    "SoundA=%u SoundB=%u SoundLevel=%u SoundBase=%u PWM=%u%% RPMBase=%u SETTLE=%u\r\n",
                    rpm,
                    vibration,
                    vib_baseline,
                    sound_a,
                    sound_b,
                    sound_level,
                    sound_baseline,
                    motor_pwm_percent(),
                    rpm_pwm_baseline,
                    g_motor_settle
                );
            }

                usleep(100000U);
            }
        }
        else xil_printf("Unknown command\r\n");
    }
}
