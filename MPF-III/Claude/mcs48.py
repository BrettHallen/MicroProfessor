import sys

# Complete Intel MCS-48 (8048/8035) opcode table.
# Format per opcode: (mnemonic_template, length)
# Templates: {d}=immediate byte #xx, {a}=addr byte (combined with page bits), {b}=branch addr (page-local)
R = lambda n: f"R{n}"
T = {}
def s(op,mn,ln): T[op]=(mn,ln)

s(0x00,"NOP",1)
s(0x02,"OUTL BUS,A",1)
s(0x03,"ADD A,#{d}",2)
s(0x04,"JMP {j}",2)
s(0x05,"EN I",1)
s(0x07,"DEC A",1)
s(0x08,"INS A,BUS",1)
s(0x09,"IN A,P1",1)
s(0x0A,"IN A,P2",1)
s(0x0C,"MOVD A,P4",1); s(0x0D,"MOVD A,P5",1); s(0x0E,"MOVD A,P6",1); s(0x0F,"MOVD A,P7",1)
s(0x10,"INC @R0",1); s(0x11,"INC @R1",1)
s(0x12,"JB0 {b}",2)
s(0x13,"ADDC A,#{d}",2)
s(0x14,"CALL {j}",2)   # page0 call (a10-8=000)
s(0x15,"DIS I",1)
s(0x16,"JTF {b}",2)
s(0x17,"INC A",1)
for i in range(8): s(0x18+i,f"INC R{i}",1)
s(0x20,"XCH A,@R0",1); s(0x21,"XCH A,@R1",1)
s(0x23,"MOV A,#{d}",2)
s(0x24,"JMP {j}",2)
s(0x25,"EN TCNTI",1)
s(0x26,"JNT0 {b}",2)
s(0x27,"CLR A",1)
for i in range(8): s(0x28+i,f"XCH A,R{i}",1)
s(0x30,"XCHD A,@R0",1); s(0x31,"XCHD A,@R1",1)
s(0x32,"JB1 {b}",2)
s(0x34,"CALL {j}",2)
s(0x35,"DIS TCNTI",1)
s(0x36,"JT0 {b}",2)
s(0x37,"CPL A",1)
s(0x39,"OUTL P1,A",1); s(0x3A,"OUTL P2,A",1)
s(0x3C,"MOVD P4,A",1); s(0x3D,"MOVD P5,A",1); s(0x3E,"MOVD P6,A",1); s(0x3F,"MOVD P7,A",1)
s(0x40,"ORL A,@R0",1); s(0x41,"ORL A,@R1",1)
s(0x42,"MOV A,T",1)
s(0x43,"ORL A,#{d}",2)
s(0x44,"JMP {j}",2)
s(0x45,"STRT CNT",1)
s(0x46,"JNT1 {b}",2)
s(0x47,"SWAP A",1)
for i in range(8): s(0x48+i,f"ORL A,R{i}",1)
s(0x50,"ANL A,@R0",1); s(0x51,"ANL A,@R1",1)
s(0x52,"JB2 {b}",2)
s(0x53,"ANL A,#{d}",2)
s(0x54,"CALL {j}",2)
s(0x55,"STRT T",1)
s(0x56,"JT1 {b}",2)
s(0x57,"DA A",1)
for i in range(8): s(0x58+i,f"ANL A,R{i}",1)
s(0x60,"ADD A,@R0",1); s(0x61,"ADD A,@R1",1)
s(0x62,"MOV T,A",1)
s(0x64,"JMP {j}",2)
s(0x65,"STOP TCNT",1)
s(0x67,"RRC A",1)
for i in range(8): s(0x68+i,f"ADD A,R{i}",1)
s(0x70,"ADDC A,@R0",1); s(0x71,"ADDC A,@R1",1)
s(0x72,"JB3 {b}",2)
s(0x74,"CALL {j}",2)
s(0x75,"ENT0 CLK",1)
s(0x76,"JF1 {b}",2)
s(0x77,"RR A",1)
for i in range(8): s(0x78+i,f"ADDC A,R{i}",1)
s(0x80,"MOVX A,@R0",1); s(0x81,"MOVX A,@R1",1)
s(0x83,"RET",1)
s(0x84,"JMP {j}",2)
s(0x85,"CLR F0",1)
s(0x86,"JNI {b}",2)
s(0x88,"ORL BUS,#{d}",2)
s(0x89,"ORL P1,#{d}",2)
s(0x8A,"ORL P2,#{d}",2)
s(0x8C,"ORLD P4,A",1); s(0x8D,"ORLD P5,A",1); s(0x8E,"ORLD P6,A",1); s(0x8F,"ORLD P7,A",1)
s(0x90,"MOVX @R0,A",1); s(0x91,"MOVX @R1,A",1)
s(0x92,"JB4 {b}",2)
s(0x93,"RETR",1)
s(0x94,"CALL {j}",2)
s(0x95,"CPL F0",1)
s(0x96,"JNZ {b}",2)
s(0x97,"CLR C",1)
s(0x98,"ANL BUS,#{d}",2)
s(0x99,"ANL P1,#{d}",2)
s(0x9A,"ANL P2,#{d}",2)
s(0x9C,"ANLD P4,A",1); s(0x9D,"ANLD P5,A",1); s(0x9E,"ANLD P6,A",1); s(0x9F,"ANLD P7,A",1)
s(0xA0,"MOV @R0,A",1); s(0xA1,"MOV @R1,A",1)
s(0xA3,"MOVP A,@A",1)
s(0xA4,"JMP {j}",2)
s(0xA5,"CLR F1",1)
s(0xA7,"CPL C",1)
for i in range(8): s(0xA8+i,f"MOV R{i},A",1)
s(0xB0,"MOV @R0,#{d}",2); s(0xB1,"MOV @R1,#{d}",2)
s(0xB2,"JB5 {b}",2)
s(0xB3,"JMPP @A",1)
s(0xB4,"CALL {j}",2)
s(0xB5,"CPL F1",1)
s(0xB6,"JF0 {b}",2)
for i in range(8): s(0xB8+i,f"MOV R{i},#{{d}}",2)
s(0xC4,"JMP {j}",2)
s(0xC5,"SEL RB0",1)
s(0xC6,"JZ {b}",2)
s(0xC7,"MOV A,PSW",1)
for i in range(8): s(0xC8+i,f"DEC R{i}",1)
s(0xD0,"XRL A,@R0",1); s(0xD1,"XRL A,@R1",1)
s(0xD2,"JB6 {b}",2)
s(0xD3,"XRL A,#{d}",2)
s(0xD4,"JMP {j}",2)
s(0xD5,"SEL RB1",1)
s(0xD7,"MOV PSW,A",1)
for i in range(8): s(0xD8+i,f"XRL A,R{i}",1)
s(0xE3,"MOVP3 A,@A",1)
s(0xE4,"JMP {j}",2)
s(0xE5,"SEL MB0",1)
s(0xE6,"JNC {b}",2)
s(0xE7,"RL A",1)
for i in range(8): s(0xE8+i,f"DJNZ R{i},{{b}}",2)
s(0xF0,"MOV A,@R0",1); s(0xF1,"MOV A,@R1",1)
s(0xF2,"JB7 {b}",2)
s(0xF4,"CALL {j}",2)
s(0xF5,"SEL MB1",1)
s(0xF6,"JC {b}",2)
s(0xF7,"RLC A",1)
for i in range(8): s(0xF8+i,f"MOV A,R{i}",1)

def decode(data, addr, base):
    """decode one instruction at file index addr (runtime = addr-base+0). returns (runtime_addr,bytes,text,length,target)"""
    op=data[addr]
    rt=addr-base
    if op not in T:
        return (rt,[op],f".DB ${op:02X}",1,None)  # undefined -> data byte
    mn,ln=T[op]
    target=None
    if ln==2:
        b2=data[addr+1]
        if "{d}" in mn:
            text=mn.format(d=f"${b2:02X}")
        elif "{b}" in mn:
            # page-local branch: high 3 bits of target = high bits of (rt+? ) ; for 2-byte cond jumps target page = page of byte following? Actually addr field a0-a7 from b2, a8-a10 from current page (PC during fetch of 2nd byte).
            page=( (rt+1) >>8)&0x7  # PC points to 2nd byte's page
            tgt=(page<<8)|b2
            target=tgt
            text=mn.format(b=f"${tgt:03X}")
        elif "{j}" in mn:
            a8_10=(op>>5)&0x7
            tgt=(a8_10<<8)|b2
            target=tgt
            text=mn.format(j=f"${tgt:03X}")
        else:
            text=mn
        return (rt,[op,b2],text,2,target)
    else:
        return (rt,[op],mn,1,None)

if __name__=="__main__":
    data=open(sys.argv[1],'rb').read()
    base=0x800
    # code regions (runtime addrs): 0x000-0x2FF and 0x390-0x3FF ; data 0x300-0x38F
    # We'll linear-sweep code regions.
    def sweep(start,end):
        a=base+start
        out=[]
        while a < base+end:
            rt,bs,txt,ln,tgt=decode(data,a,base)
            out.append((rt,bs,txt,tgt))
            a+=ln
        return out
    import json
    res={"code1":sweep(0x000,0x300),"code2":sweep(0x390,0x400)}
    # dump
    for k in ["code1","code2"]:
        for rt,bs,txt,tgt in res[k]:
            bb=" ".join(f"{x:02X}" for x in bs)
            print(f"{rt:03X}: {bb:<9} {txt}")
