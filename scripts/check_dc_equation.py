"""Mathematical check only. This is NOT RTL simulation or timing closure."""
import random
rng = random.Random(20261103)
def s32(x):
    x &= 0xffffffff
    return x-(1<<32) if x>>31 else x
def s16(x):
    x &= 0xffff
    return x-(1<<16) if x>>15 else x
cases=[-(1<<31),-(1<<31)+1,-32768,-1,0,1,32767,(1<<31)-1]
cases += [rng.randrange(-(1<<31),(1<<31)) for _ in range(300000)]
for alpha in (32604, 32767, -16384, -32768):
  for y in cases:
    hi=s16(y>>16)
    lo=y&0xffff
    orig=(y*alpha)>>15
    split=(hi*alpha)*2+((lo*alpha)>>15)
    assert orig==split, (y,alpha,orig,split)
    din=s16(rng.randrange(1<<16));xp=s16(rng.randrange(1<<16))
    old=s32(din-xp+orig)
    new=s32(din-xp+split)
    assert old==new
  print('EXACT_PARTIAL_PRODUCT_CHECK_PASS alpha=',alpha,' cases=',len(cases))
