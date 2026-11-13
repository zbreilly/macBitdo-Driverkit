#include "../../ReceiverBridge/Rumble.h"

int legacy_self_test(void){return rumbleSelfTest();}
int legacy_decode(unsigned id,const uint8_t *bytes,size_t length,
    uint8_t *low,uint8_t *high,double *on,double *delay,unsigned *cycles){
    RumbleEffect effect;
    int accepted=decodeRumble(id,bytes,length,&effect);
    if(accepted){*low=effect.low;*high=effect.high;*on=effect.on;*delay=effect.delay;*cycles=effect.cycles;}
    return accepted;
}
void legacy_packet(uint8_t low,uint8_t high,uint8_t out[8]){encodeRumble(low,high,out);}
void legacy_at(uint8_t low,uint8_t high,double on,double delay,unsigned cycles,
    double elapsed,uint8_t *a,uint8_t *b){
    RumbleEffect effect={low,high,on,delay,cycles};rumbleAt(effect,elapsed,a,b);
}
