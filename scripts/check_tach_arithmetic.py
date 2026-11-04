# Verify intended 16-bit output behavior for PPR=20.
for pulse_cnt in range(65536):
    original = ((pulse_cnt * 60) // 20) & 0xffff
    optimized = ((pulse_cnt << 1) + pulse_cnt) & 0xffff
    assert original == optimized, (pulse_cnt, original, optimized)
print('TACH_ARITH_EQ_PASS checked=65536 ppr=20')
