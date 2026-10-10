import re, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import sys
R=sys.argv[1] if len(sys.argv)>1 else "resultados"
SURF="#fcfcfb"; T1="#0b0b0b"; T2="#52514e"; GRID="#e4e3df"; BLUE="#2a78d6"
def load(ds):
    xs,ys=[],[]
    for l in open(f"{R}/{ds}/monitor/monitor.log"):
        m=re.match(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)",l)
        if m: xs.append(int(m[1])); ys.append(int(m[6]))
    t={}
    for l in open(f"{R}/{ds}/monitor/tiempos.txt"):
        for k,key in [("STALE","Paso a STALE"),("MUERTO","Marcado como MUERTO"),("ELIM","eliminadas del mapa"),("REC","Re-replicacion completa")]:
            if key in l: t[k]=int(re.findall(r"(\d+) s",l)[0])
    return xs,ys,t
plt.rcParams.update({"font.family":"DejaVu Sans","font.size":10})
fig,axes=plt.subplots(2,1,figsize=(10,6.4),sharex=True,facecolor=SURF)
for ax,ds,tot in zip(axes,["1GB","10GB"],[8,80]):
    xs,ys,t=load(ds); ax.set_facecolor(SURF)
    ax.step(xs,ys,where="post",color=BLUE,lw=2)
    ax.fill_between(xs,ys,step="post",color=BLUE,alpha=0.12,lw=0)
    top=max(ys)*1.35
    marks=[("STALE","STALE"),("MUERTO","MUERTO"),("ELIM","Réplicas de DN2\neliminadas"),("REC","Recuperado")]
    for i,(k,lab) in enumerate(marks):
        x=t[k]; ax.axvline(x,color=T2,lw=1,ls=(0,(3,3)))
        nxt=t[marks[i+1][0]] if i+1<len(marks) else 10**9
        if nxt-x<15:   # el siguiente evento esta muy cerca: etiqueta a la izquierda, a media altura
            ax.text(x-2,top*0.6,f"{lab}\n{x} s",va="top",ha="right",fontsize=8.5,color=T2)
        else:
            ax.text(x+2,top*0.97,f"{lab}\n{x} s",va="top",ha="left",fontsize=8.5,color=T2)
    ax.set_ylim(0,top); ax.set_xlim(0,300)
    ax.set_ylabel("Bloques sub-replicados",color=T2)
    ax.set_title(f"Dataset {ds}  ·  {max(ys)} de {tot} bloques afectados  ·  re-replicación en {t['REC']-t['ELIM']} s",loc="left",fontsize=11,color=T1,fontweight="bold")
    for s in ["top","right"]: ax.spines[s].set_visible(False)
    for s in ["left","bottom"]: ax.spines[s].set_color(GRID)
    ax.tick_params(colors=T2); ax.grid(axis="y",color=GRID,lw=0.8); ax.set_axisbelow(True)
axes[1].set_xlabel("Segundos desde que se detuvo DN2",color=T2)
fig.suptitle("GRUPO 01 · LG15 · Recuperación de réplicas tras la caída de DN2",x=0.01,ha="left",fontsize=13,color=T1,fontweight="bold")
fig.tight_layout(rect=(0,0,1,0.95))
fig.savefig("diagrama/recuperacion_replicas.png",dpi=150,facecolor=SURF)
