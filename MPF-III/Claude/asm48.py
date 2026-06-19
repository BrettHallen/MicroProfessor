# Independent two-pass MCS-48 assembler (validation tool).
import re,sys,mcs48
T=mcs48.T  # opcode->(template,len) : authoritative ISA spec

# Build skeleton -> (opcode, kind, len). kind in {'none','d','b','j'}
SK={}
for op,(tmpl,ln) in T.items():
    kind='none'
    if '{d}' in tmpl: kind='d'
    elif '{b}' in tmpl: kind='b'
    elif '{j}' in tmpl: kind='j'
    sk=tmpl.replace('{d}','@').replace('{b}','@').replace('{j}','@')
    sk=re.sub(r'\s+',' ',sk).strip().upper().replace(', ',',')
    SK[sk]=(op,kind,ln)

def num(tok):
    tok=tok.strip()
    if tok.startswith('#'): tok=tok[1:]
    if tok.startswith('$'): return int(tok[1:],16)
    if re.fullmatch(r'0?[0-9A-Fa-f]+H',tok): return int(tok[:-1],16)
    if re.fullmatch(r'[0-9]+',tok): return int(tok)
    return None

def skeleton(mn,labels):
    s=re.sub(r'\s+',' ',mn).strip().upper().replace(', ',',')
    # immediate
    s=re.sub(r'#\$?[0-9A-Fa-f]+H?','#@',s)
    # address: $XXX  or label name
    s=re.sub(r'\$[0-9A-Fa-f]{2,3}','@',s)
    for L in sorted(labels,key=len,reverse=True):
        s=re.sub(r'\b'+re.escape(L.upper())+r'\b','@',s)
    return s

def assemble(text):
    lines=text.splitlines()
    sym={}; labels=set()
    # collect EQU + label names first
    for ln in lines:
        l=ln.split(';',1)[0].rstrip()
        if not l.strip(): continue
        m=re.match(r'\s*([A-Za-z_]\w*)\s+EQU\s+(\S+)',l)
        if m: sym[m.group(1).upper()]=num(m.group(2)); continue
        m=re.match(r'\s*([A-Za-z_]\w*):',l)
        if m: labels.add(m.group(1).upper())
    # pass1: addresses
    pc=0; addr={}
    for ln in lines:
        l=ln.split(';',1)[0].rstrip()
        if not l.strip(): continue
        s=l.strip()
        if re.match(r'[A-Za-z_]\w*\s+EQU\s',s,re.I): continue
        if s.upper().startswith('END'): break
        m=re.match(r'(?:([A-Za-z_]\w*):)?\s*(.*)',l)
        lab,rest=m.group(1),m.group(2).strip()
        if lab: addr[lab.upper()]=pc
        if not rest: continue
        mo=re.match(r'ORG\s+(\S+)',rest,re.I)
        if mo: pc=num(mo.group(1)); 
        if mo: 
            if lab: addr[lab.upper()]=pc
            continue
        md=re.match(r'DB\s+(.*)',rest,re.I)
        if md: pc+=len([x for x in md.group(1).split(',') if x.strip()]); continue
        sk=skeleton(rest,labels)
        if sk not in SK: raise SystemExit(f"pass1 unknown: {rest!r} -> {sk!r}")
        pc+=SK[sk][2]
    sym.update(addr)
    # pass2: encode
    pc=0; out={}
    for ln in lines:
        l=ln.split(';',1)[0].rstrip()
        if not l.strip(): continue
        m=re.match(r'(?:([A-Za-z_]\w*):)?\s*(.*)',l)
        rest=m.group(2).strip()
        if re.match(r'[A-Za-z_]\w*\s+EQU\s',rest,re.I): continue
        if rest.upper().startswith('END'): break
        mo=re.match(r'ORG\s+(\S+)',rest,re.I)
        if mo: pc=num(mo.group(1)); continue
        if not rest: continue
        md=re.match(r'DB\s+(.*)',rest,re.I)
        if md:
            for x in md.group(1).split(','):
                x=x.strip()
                if x: out[pc]=num(x)&0xFF; pc+=1
            continue
        sk=skeleton(rest,labels); op,kind,length=SK[sk]
        out[pc]=op
        if length==2:
            # find operand value
            if kind=='d':
                v=num(re.search(r'#(\$?[0-9A-Fa-f]+H?)',rest).group(1))
            else:
                # address operand: label or $xxx (last token)
                tok=re.split(r'[,\s]+',rest)[-1]
                v=sym[tok.upper()] if re.match(r'[A-Za-z_]',tok) else num(tok)
                if kind=='j':
                    out[pc]=(op&0x1F)|(((v>>8)&0x7)<<5)
                    v=v&0xFF
                else: # b : page-local, just low byte
                    v=v&0xFF
            out[pc+1]=v&0xFF; pc+=2
        else: pc+=1
    return out

if __name__=="__main__":
    out=assemble(open(sys.argv[1]).read())
    lo=min(out); hi=max(out)
    img=bytearray([0xFF]*(hi+1))
    for a,b in out.items(): img[a]=b
    # compare to ROM region 0x800-0xBFF (runtime 0x000-0x3FF)
    rom=open(sys.argv[2],'rb').read()[0x800:0x800+0x400]
    asm=bytes(img[0:0x400])
    if asm==rom:
        print(f"ROUND-TRIP OK: assembled {len(asm)} bytes == ROM[0x800:0xC00] EXACT MATCH")
    else:
        print("MISMATCH:")
        for i in range(0x400):
            if asm[i]!=rom[i]:
                print(f"  {i:03X}: asm={asm[i]:02X} rom={rom[i]:02X}")
