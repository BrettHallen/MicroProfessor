# Minimal MCS-48 emulator to run the key-handler for each scan index R6.
import sys
ROM=open("/sessions/confident-brave-hawking/mnt/Multitech MPF-III Keyboard/MPF-III_ROM_KEYBOARD_U5_2732_46D4227A.BIN",'rb').read()
BASE=0x800
def rd(pc): return ROM[BASE+pc]

class CPU:
    def __init__(self,T0,T1,INT):
        self.A=0;self.PC=0;self.C=0;self.rb=0;self.mb=0
        self.reg=[ [0]*8,[0]*8 ]   # two banks; regs map to RAM 0-7 / 24-31
        self.ram=[0]*64
        self.T0=T0;self.T1=T1;self.INT=INT
        self.P1=0xC7;self.P2=0xFF;self.BUS=0xFF
        self.steps=0
    def R(self,n): return self.reg[self.rb][n]
    def setR(self,n,v): self.reg[self.rb][n]=v&0xFF
    def run(self,start,stop_at,maxs=20000):
        self.PC=start
        while self.steps<maxs:
            self.steps+=1
            if self.PC in stop_at: return self.PC
            op=rd(self.PC); self.PC=(self.PC+1)&0xFFF
            self.exec(op)
        raise SystemExit("runaway")
    def imm(self):
        v=rd(self.PC);self.PC=(self.PC+1)&0xFFF;return v
    def jmp_addr(self,op):
        lo=self.imm(); return ((op>>5)&7)<<8 | lo
    def br(self):
        lo=self.imm(); return (self.PC&0x700)|lo  # page-local (PC already advanced)
    def exec(self,op):
        A=self.A
        if op==0x00: pass
        elif op==0x27: self.A=0
        elif op==0x37: self.A=(~A)&0xFF
        elif op==0x17: self.A=(A+1)&0xFF
        elif op==0x07: self.A=(A-1)&0xFF
        elif op==0xE7: self.A=((A<<1)|(A>>7))&0xFF           # RL
        elif op==0xF7: r=(A<<1)|self.C; self.C=(A>>7)&1; self.A=r&0xFF   # RLC
        elif op==0x77: self.A=((A>>1)|(A<<7))&0xFF           # RR
        elif op==0x67: r=(A>>1)|(self.C<<7); self.C=A&1; self.A=r&0xFF   # RRC
        elif op==0x47: self.A=((A<<4)|(A>>4))&0xFF           # SWAP
        elif op==0x97: self.C=0
        elif op==0xA7: self.C^=1
        # MOV A,#d / ANL/ORL/XRL/ADD A,#d
        elif op==0x23: self.A=self.imm()
        elif op==0x53: self.A=A&self.imm()
        elif op==0x43: self.A=A|self.imm()
        elif op==0xD3: self.A=A^self.imm()
        elif op==0x03: v=self.imm(); s=A+v; self.C=1 if s>0xFF else 0; self.A=s&0xFF
        elif op==0x13: v=self.imm(); s=A+v+self.C; self.C=1 if s>0xFF else 0; self.A=s&0xFF
        # MOV A,Rn / Rn,A / @Rn
        elif 0xF8<=op<=0xFF: self.A=self.R(op&7)
        elif 0xA8<=op<=0xAF: self.setR(op&7,A)
        elif 0xB8<=op<=0xBF: self.setR(op&7,self.imm())
        elif op in (0xF0,0xF1): self.A=self.ram[self.R(op&1)&0x3F]
        elif op in (0xA0,0xA1): self.ram[self.R(op&1)&0x3F]=A
        elif op in (0xB0,0xB1): self.ram[self.R(op&1)&0x3F]=self.imm()
        elif 0x68<=op<=0x6F: v=self.R(op&7); s=A+v; self.C=1 if s>0xFF else 0; self.A=s&0xFF
        elif 0x48<=op<=0x4F: self.A=A|self.R(op&7)
        elif 0x58<=op<=0x5F: self.A=A&self.R(op&7)
        elif 0xD8<=op<=0xDF: self.A=A^self.R(op&7)
        elif op in (0x60,0x61): v=self.ram[self.R(op&1)&0x3F]; s=A+v;self.C=1 if s>0xFF else 0;self.A=s&0xFF
        elif op in (0x40,0x41): self.A=A|self.ram[self.R(op&1)&0x3F]
        elif op in (0x50,0x51): self.A=A&self.ram[self.R(op&1)&0x3F]
        elif op in (0xD0,0xD1): self.A=A^self.ram[self.R(op&1)&0x3F]
        elif 0x18<=op<=0x1F: self.setR(op&7,self.R(op&7)+1)
        elif 0xC8<=op<=0xCF: self.setR(op&7,self.R(op&7)-1)
        elif op in (0x10,0x11): i=self.R(op&1)&0x3F; self.ram[i]=(self.ram[i]+1)&0xFF
        elif 0x28<=op<=0x2F: n=op&7; t=self.R(n); self.setR(n,A); self.A=t
        elif op in (0x20,0x21): i=self.R(op&1)&0x3F; t=self.ram[i]; self.ram[i]=A; self.A=t
        elif op in (0x30,0x31): i=self.R(op&1)&0x3F; t=self.ram[i]; self.ram[i]=(self.ram[i]&0xF0)|(A&0xF); self.A=(A&0xF0)|(t&0xF)
        # MOVP3 / MOVP
        elif op==0xE3: self.A=rd(0x300|A)
        elif op==0xA3: self.A=rd((self.PC&0xF00)|A)
        # bank/flags
        elif op==0xC5: self.rb=0
        elif op==0xD5: self.rb=1
        elif op==0xE5: self.mb=0
        elif op==0xF5: self.mb=1
        elif op==0xC7: self.A=(self.C<<7)|0x08|(self.rb<<4)  # MOV A,PSW approx
        elif op==0xD7: self.rb=(A>>4)&1; self.C=(A>>7)&1
        # ports
        elif op==0x09: self.A=self.P1
        elif op==0x0A: self.A=self.P2
        elif op==0x08: self.A=self.BUS
        elif op==0x02: self.BUS=A
        elif op==0x39: self.P1=A
        elif op==0x3A: self.P2=A
        elif op==0x88: self.BUS=self.BUS|self.imm()
        elif op==0x89: self.P1=self.P1|self.imm()
        elif op==0x8A: self.P2=self.P2|self.imm()
        elif op==0x98: self.BUS=self.BUS&self.imm()
        elif op==0x99: self.P1=self.P1&self.imm()
        elif op==0x9A: self.P2=self.P2&self.imm()
        elif op==0x42: self.A=0  # MOV A,T (timer) - not used in path
        elif op==0x62: pass
        # control
        elif op in (0x05,0x15,0x25,0x35,0x45,0x55,0x65,0x75,0x85,0x95,0xA5,0xB5): pass # EN/DIS/STRT/STOP/CLR F etc (no effect for our trace) -- careful 0x95=CPL F0,0xB5=CPL F1,0xA5=CLR F1,0x85=CLR F0,0x55=STRT T,0x65=STOP TCNT,0x45=STRT CNT,0x35=DIS TCNTI,0x25=EN TCNTI,0x15=DIS I,0x05=EN I,0x75=ENT0
        # jumps
        elif op in (0x04,0x24,0x44,0x64,0x84,0xA4,0xC4,0xE4): self.PC=self.jmp_addr(op)
        elif op in (0x14,0x34,0x54,0x74,0x94,0xB4,0xD4,0xF4): self.jmp_addr(op) # CALL: ignore (no nested side effects needed)... but some calls matter
        elif op==0x83 or op==0x93: pass  # RET/RETR handled by stop_at
        elif op==0xB3: self.PC=(self.PC&0xF00)|self.A
        # conditional
        elif op==0x96: t=self.br();  self.PC=t if self.A!=0 else self.PC
        elif op==0xC6: t=self.br();  self.PC=t if self.A==0 else self.PC
        elif op==0xE6: t=self.br();  self.PC=t if self.C==0 else self.PC
        elif op==0xF6: t=self.br();  self.PC=t if self.C==1 else self.PC
        elif op==0x26: t=self.br();  self.PC=t if self.T0==0 else self.PC
        elif op==0x36: t=self.br();  self.PC=t if self.T0==1 else self.PC
        elif op==0x46: t=self.br();  self.PC=t if self.T1==0 else self.PC
        elif op==0x56: t=self.br();  self.PC=t if self.T1==1 else self.PC
        elif op==0x86: t=self.br();  self.PC=t if self.INT==0 else self.PC
        elif op==0x16: t=self.br();  self.PC=t  # JTF: timer flag -> assume 0 normally; not taken
        elif op==0x76 or op==0xB6: self.br()  # JF1/JF0 not taken
        elif (op&0x1F)==0x12:  # JBb
            b=(op>>5)&7; t=self.br(); self.PC=t if (self.A>>b)&1 else self.PC
        elif 0xE8<=op<=0xEF: n=op&7; t=self.br(); self.setR(n,self.R(n)-1); self.PC=t if self.R(n)!=0 else self.PC
        else:
            raise SystemExit(f"unimpl op {op:02X} at {self.PC-1:03X}")

# Map handler output: run KEY_HANDLER (0x26F) with given R6; capture [0x2E] and [0x38].
def keycode(R6,T0=1,T1=1,INT=1):
    c=CPU(T0,T1,INT)
    c.rb=1
    c.setR(6,R6)           # RB1.R6 = raw key index
    c.setR(7,0)            # flags clear (no caps/ctrl)
    # stop at any RETR/RET that returns from handler back to caller level
    # Simplest: run until we hit the common RETR points; collect code at [0x2E].
    stops={0x224,0x2ED,0x2F6,0x2FC}
    try:
        c.run(0x26F,stops)
    except SystemExit as e:
        return ("ERR:"+str(e),None)
    return (c.ram[0x2E], c.ram[0x38])

if __name__=="__main__":
    # anchors
    for R6,exp in [(0x00,'1=B1'),(0x07,'8=B8'),(0x20,'E=E5'),(0x25,'A=E1')]:
        print(f"R6={R6:02X} -> [2E]={keycode(R6)[0]} (expect {exp})")
