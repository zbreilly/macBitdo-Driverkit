#include <cassert>
#include <cstdio>
#include <cmath>
#include <initializer_list>
#include "../Driver/ReceiverProtocol.h"
extern "C" {
int legacy_self_test(void);
int legacy_decode(unsigned,const uint8_t *,size_t,uint8_t *,uint8_t *,double *,double *,unsigned *);
void legacy_packet(uint8_t,uint8_t,uint8_t [8]);
void legacy_at(uint8_t,uint8_t,double,double,unsigned,double,uint8_t *,uint8_t *);
int legacy_input(const uint8_t *,size_t,uint8_t [17]);
}
using namespace ReceiverProtocol;

int main() {
    const uint8_t neutral[]={1,0,128,255,127,0,128,255,127,0,0,0,0,0,0,0,0};
    uint8_t report[17];encode({},report);
    assert(!memcmp(report,neutral,sizeof(report)));
    const uint8_t packet[]={0,20,0x40,0x14,0,255,0,128,255,127,255,255,0,0,0,0,0,0,0,0};
    State state{};assert(decode(packet,sizeof(packet),&state));
    assert(state.buttons==0x1440&&state.lx==-32768&&state.ly==32767&&state.rx==-1&&state.ry==0);
    const uint8_t boundary[]={1,0,0,0,0,255,127,255,127,0,0,255,3,0,1,48,0};
    encode(state,report);assert(!memcmp(report,boundary,sizeof(report)));
    assert(!decode(packet,19,&state)&&!decode(nullptr,20,&state));
    uint8_t malformed[20];memcpy(malformed,packet,20);malformed[1]=19;
    assert(!decode(malformed,20,&state));
    const uint16_t directions[]={1,9,8,10,2,6,4,5};
    for(unsigned i=0;i<8;i++){state={};state.buttons=directions[i];encode(state,report);assert(report[13]==i+1);}
    for(uint16_t b:{uint16_t(0),uint16_t(3),uint16_t(12),uint16_t(15)}){
        state={};state.buttons=b;encode(state,report);assert(report[13]==0);
    }
    uint16_t last=0;
    for(unsigned value=0;value<=255;value++){
        state={};state.lt=(uint8_t)value;state.rt=(uint8_t)value;encode(state,report);
        uint16_t lt=(uint16_t)(report[9]|report[10]<<8);
        assert(lt>=last&&lt<=1023&&report[9]==report[11]&&report[10]==report[12]);last=lt;
    }
    assert(last==1023);
    uint8_t input[20]={0,20},expected[17];
    for(unsigned buttons=0;buttons<=65535;buttons++){
        put16(input+2,(uint16_t)buttons);input[4]=buttons&255;input[5]=buttons>>8;
        assert(legacy_input(input,20,expected));assert(decode(input,20,&state));
        encode(state,report);assert(!memcmp(report,expected,17));
    }
    const int16_t edges[]={-32768,-1,0,1,32767};
    for(int16_t lx:edges)for(int16_t ly:edges)for(int16_t rx:edges)for(int16_t ry:edges){
        put16(input+6,(uint16_t)lx);put16(input+8,(uint16_t)ly);
        put16(input+10,(uint16_t)rx);put16(input+12,(uint16_t)ry);
        assert(legacy_input(input,20,expected));assert(decode(input,20,&state));
        encode(state,report);assert(!memcmp(report,expected,17));
    }
    assert(legacy_self_test()==0);
    // Compare every byte magnitude and motor-mask combination with the
    // original hardware-validated C implementation, including out-of-range
    // magnitudes, trigger-only masks and leading-ID handling.
    for(unsigned mask=0;mask<16;mask++)for(unsigned low=0;low<256;low++)for(unsigned high=0;high<256;high++){
        uint8_t bytes[]={3,(uint8_t)mask,77,99,(uint8_t)low,(uint8_t)high,10,3,1};
        RumbleEffect current{},previous{};
        assert(decodeRumble(3,bytes,9,&current)==legacy_decode(3,bytes,9,&previous.low,&previous.high,&previous.on,&previous.delay,&previous.cycles));
        assert(current.low==previous.low&&current.high==previous.high&&current.on==previous.on&&
            current.delay==previous.delay&&current.cycles==previous.cycles);
        uint8_t a[8],b[8];encodeRumble(current.low,current.high,a);legacy_packet(previous.low,previous.high,b);
        assert(!memcmp(a,b,8));
    }
    RumbleEffect effect{128,255,.5,.1,2};
    for(double t:{-.1,0.,.05,.1,.3,.6,.7,1.1,1.3}){
        uint8_t a,b,c,d;rumbleAt(effect,t,&a,&b);legacy_at(128,255,.5,.1,2,t,&c,&d);assert(a==c&&b==d);
    }
    puts("PASS: wire fixtures, 65,536 legacy button combinations, 625 stick-boundary combinations, and 1,048,576 legacy rumble comparisons.");
}
