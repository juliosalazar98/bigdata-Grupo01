#!/usr/bin/env bash
# =====================================================================
#  LG15 - Tolerancia a fallos y replicacion de datos en HDFS - GRUPO 01
#  Se ejecuta DENTRO del contenedor clientnode, como usuario hdfs:
#
#    bash /tmp/lg15/lg15.sh estado   <1GB|10GB> <antes|despues|restaurado>
#    bash /tmp/lg15/lg15.sh monitor  <1GB|10GB> [DN2]
#    bash /tmp/lg15/lg15.sh comparar <1GB|10GB>
#    bash /tmp/lg15/lg15.sh guardar
#    bash /tmp/lg15/lg15.sh check     (verifica que el monitoreo puede leer al NameNode)
#
#  Los resultados quedan en /tmp/lg15_out/<dataset>/<momento>/
#  y con "guardar" se copian a HDFS en /grupo01/resultados/
# =====================================================================
set -u
GRUPO="grupo01"
OUT="/tmp/lg15_out"
JMX_URL='http://namenode:9870/jmx?qry=Hadoop:service=NameNode,name=FSNamesystem*'

hora()    { TZ=UTC+4 date '+%Y-%m-%d %H:%M:%S'; }          # hora de Bolivia (UTC-4)
ruta_ds() { echo "/${GRUPO}/dataset_$1/dataset_${GRUPO}_$1"; }
titulo()  { echo "=================================================================="; echo " GRUPO 01 - LG15 - $1 - $(hora)"; echo "=================================================================="; }

# --- Nodos: "ip etiqueta hostname estado" a partir de dfsadmin -report ---
nodos_desde_report() {
  awk '
    /^Live datanodes/ {st="VIVO"} /^Dead datanodes/ {st="MUERTO"}
    /^Name: /     {split($2,a,":"); ip=a[1]}
    /^Hostname: / {h=$2; l=h; if(h=="hadoopnode")l="DN1"; if(h=="hadoopnode2")l="DN2"; if(h=="hadoopnode3")l="DN3"; print ip, l, h, st}
  ' "$1"
}

# --- Tabla de bloques: "indice id replicas nodos" a partir de fsck ---
bloques_desde_fsck() {   # $1 = nodos.txt  $2 = fsck.txt
  awk '
    FNR==NR {lab[$1]=$2; next}
    /^[0-9]+\. BP-/ {
      idx=$1; sub(/\.$/,"",idx)
      split($2,b,":"); blk=b[2]; sub(/_[0-9]+$/,"",blk)
      rep="?"; for(i=1;i<=NF;i++) if($i ~ /^Live_repl=/){rep=$i; sub(/Live_repl=/,"",rep)}
      n=""; s=$0
      while (match(s,/DatanodeInfoWithStorage\[[0-9.]+/)) {
        ip=substr(s,RSTART+24,RLENGTH-24); l=(ip in lab)?lab[ip]:ip
        n=n (n==""?"":",") l; s=substr(s,RSTART+RLENGTH)
      }
      if(n=="") n="-"
      print idx, blk, rep, n
    }' "$1" "$2"
}

dato_fsck() { grep -m1 "$2" "$1" | sed 's/.*:[[:space:]]*//'; }

# ---------------------------------------------------------------------
cmd_estado() {
  ds="$1"; mom="$2"; ruta=$(ruta_ds "$ds"); dir="$OUT/$ds/$mom"; mkdir -p "$dir"
  {
  titulo "DATASET $ds - ESTADO: $(echo "$mom" | tr a-z A-Z)"
  hdfs dfsadmin -report > "$dir/dfsadmin_report.txt" 2>&1
  nodos_desde_report "$dir/dfsadmin_report.txt" > "$dir/nodos.txt"
  hdfs fsck "$ruta" -files -blocks -locations > "$dir/fsck.txt" 2>&1
  bloques_desde_fsck "$dir/nodos.txt" "$dir/fsck.txt" > "$dir/bloques.txt"

  echo; echo "1) ESTADO DE LOS DATANODES"
  sort -k2 "$dir/nodos.txt" | awk '{printf "   %-4s %-12s %-15s %s\n",$2,$3,$1,$4}'

  echo; echo "2) ESTADO DEL ARCHIVO  $ruta"
  echo "   Estado HDFS (fsck)        : $(dato_fsck "$dir/fsck.txt" 'Status:')"
  echo "   Total de bloques          : $(dato_fsck "$dir/fsck.txt" 'Total blocks (validated)')"
  echo "   Replicacion configurada   : $(dato_fsck "$dir/fsck.txt" 'Default replication factor')"
  echo "   Replicacion promedio      : $(dato_fsck "$dir/fsck.txt" 'Average block replication')"
  echo "   Bloques sub-replicados    : $(dato_fsck "$dir/fsck.txt" 'Under-replicated blocks')"
  echo "   Bloques sobre-replicados  : $(dato_fsck "$dir/fsck.txt" 'Over-replicated blocks')"
  echo "   Bloques faltantes         : $(dato_fsck "$dir/fsck.txt" 'Missing blocks:')"
  echo "   Bloques corruptos         : $(dato_fsck "$dir/fsck.txt" 'Corrupt blocks:')"

  echo; echo "3) REPLICAS POR DATANODE (que bloques guarda cada uno)"
  awk '{n=split($4,a,","); for(i=1;i<=n;i++){c[a[i]]++; l[a[i]]=l[a[i]] (l[a[i]]==""?"":" ") $1}}
       END{for(k in c) printf "   %-4s %3d replicas -> bloques: %s\n",k,c[k],l[k]}' "$dir/bloques.txt" | sort

  total=$(wc -l < "$dir/bloques.txt")
  echo; echo "4) DETALLE DE BLOQUES (bloque, id, replicas vivas, ubicacion)"
  if [ "$total" -le 12 ]; then
    awk '{printf "   %-3s %-22s repl=%-2s %s\n",$1,$2,$3,$4}' "$dir/bloques.txt"
  else
    head -8 "$dir/bloques.txt" | awk '{printf "   %-3s %-22s repl=%-2s %s\n",$1,$2,$3,$4}'
    echo "   ... ($total bloques en total, lista completa en bloques.txt)"
  fi

  echo; echo "5) ACCESO AL ARCHIVO"
  echo "   Checksum: $(hdfs dfs -checksum "$ruta" 2>/dev/null | awk '{print $2, $3}')"
  t1=$(date +%s); bytes=$(hdfs dfs -cat "$ruta" 2> "$dir/lectura_warn.txt" | wc -c); t2=$(date +%s)
  echo "   Lectura completa: $bytes bytes en $((t2-t1)) s"
  } 2>&1 | tee "$dir/resumen.txt"
}

# ---------------------------------------------------------------------
jmx_val() { echo "$1" | grep -o "\"$2\" *: *[0-9-]*" | head -1 | grep -o '[0-9-]*$'; }

cmd_monitor() {
  ds="$1"; nodo="${2:-DN2}"; ruta=$(ruta_ds "$ds"); dir="$OUT/$ds/monitor"; dur="$OUT/$ds/durante"
  [ -f "$OUT/$ds/antes/nodos.txt" ] || { echo "ERROR: primero ejecuta: estado $ds antes"; return 1; }
  ipc=$(awk -v l="$nodo" '$2==l{print $1}' "$OUT/$ds/antes/nodos.txt")
  [ -n "$ipc" ] || { echo "ERROR: no encuentro la IP de $nodo en el estado antes"; return 1; }
  mkdir -p "$dir" "$dur"; log="$dir/monitor.log"; t0=$(date +%s)
  fsck_url="http://namenode:9870/fsck?ugi=hdfs&files=1&blocks=1&locations=1&path=${ruta}"
  {
  titulo "DATASET $ds - MONITOREO DE LA FALLA DE $nodo ($ipc)"
  echo " t=0 s es el momento en que $nodo quedo detenido"
  echo " EN_$nodo = bloques del dataset que el NameNode todavia ubica en $nodo"
  echo " SUB_DS   = bloques del dataset con menos de 2 replicas (sub-replicados)"
  echo
  } | tee "$log"

  # Prueba de lectura con el DataNode caido (en segundo plano)
  (
    a=$(date +%s); b=$(hdfs dfs -cat "$ruta" 2> "$dir/lectura_warn.txt" | wc -c); c=$(date +%s)
    w=$(grep -ci "failed to connect\|deadnodes\|no route\|connection refused\|exception" "$dir/lectura_warn.txt")
    echo "   >> $(hora)  LECTURA CON $nodo CAIDO: $b bytes leidos en $((c-a)) s (avisos del cliente: $w)" | tee -a "$log"
    [ "$w" -gt 0 ] && echo "   >> aviso: $(grep -i -m1 "failed to connect\|deadnodes\|no route\|connection refused\|exception" "$dir/lectura_warn.txt" | cut -c1-150)" | tee -a "$log"
  ) &
  lector=$!

  printf "%-19s %5s %5s %5s %7s %8s %7s %8s  %s\n" "HORA" "SEG" "VIVOS" "STALE" "MUERTOS" "EN_$nodo" "SUB_DS" "PENDIENT" "FASE" | tee -a "$log"
  t_stale=""; t_dead=""; t_rem=""; t_rec=""; max_sub=0
  fase="$nodo detenido; el NameNode aun no lo sabe"; ultimo=""
  while :; do
    j=$(curl -s "$JMX_URL"); f=$(curl -s "$fsck_url"); s=$(( $(date +%s) - t0 ))
    live=$(jmx_val "$j" NumLiveDataNodes); dead=$(jmx_val "$j" NumDeadDataNodes); stale=$(jmx_val "$j" NumStaleDataNodes)
    pend=$(jmx_val "$j" PendingReplicationBlocks); [ -z "$pend" ] && pend=$(jmx_val "$j" PendingReconstructionBlocks)
    live=${live:-0}; dead=${dead:-0}; stale=${stale:-0}; pend=${pend:-0}
    enc=$(echo "$f" | grep -o "DatanodeInfoWithStorage\[$ipc:" | wc -l)
    sub=$(echo "$f" | grep -m1 "Under-replicated blocks:" | grep -o '[0-9]\+' | head -1); sub=${sub:-0}
    okf=$(echo "$f" | grep -c "Status:")     # 0 si la consulta fsck fallo en esta vuelta
    [ "$sub" -gt "$max_sub" ] && max_sub=$sub
    if [ -z "$t_stale" ] && [ "$stale" -ge 1 ]; then t_stale=$s; fase="STALE: $nodo sin latidos por mas de 30 s"; fi
    if [ -z "$t_dead" ] && [ "$dead" -ge 1 ]; then t_dead=$s; fase="MUERTO: el NameNode marca a $nodo como muerto"; fi
    if [ -n "$t_dead" ] && [ -z "$t_rem" ] && [ "$okf" -gt 0 ] && [ "$enc" -eq 0 ]; then
      t_rem=$s; fase="REPLICAS DE $nodo ELIMINADAS: HDFS re-replica los bloques"
      echo "$f" > "$dur/fsck.txt"
      awk -v ip="$ipc" '$1==ip{$4="MUERTO"}1' "$OUT/$ds/antes/nodos.txt" > "$dur/nodos.txt"
      bloques_desde_fsck "$dur/nodos.txt" "$dur/fsck.txt" > "$dur/bloques.txt"
    fi
    if [ -n "$t_rem" ] && [ "$okf" -gt 0 ] && [ "$sub" -eq 0 ] && [ "$pend" -eq 0 ]; then
      t_rec=$s; fase="RECUPERADO: todos los bloques volvieron a tener 2 replicas"
    fi
    linea=$(printf "%-19s %5s %5s %5s %7s %8s %7s %8s  %s" "$(hora)" "$s" "$live" "$stale" "$dead" "$enc" "$sub" "$pend" "$fase")
    echo "$linea" | tee -a "$log" >/dev/null
    # en pantalla solo se muestran los cambios (el log guarda todo)
    clave="$live $stale $dead $enc $sub $pend $fase"
    if [ "$clave" != "$ultimo" ] || [ $((s % 10)) -eq 0 ]; then echo "$linea"; ultimo="$clave"; fi
    [ -n "$t_rec" ] && break
    [ "$s" -gt 1800 ] && { echo "Se supero el tiempo maximo de 30 min" | tee -a "$log"; break; }
    sleep 1
  done
  wait "$lector" 2>/dev/null

  {
  echo
  echo "BLOQUES DEL DATASET $ds SUB-REPLICADOS EN EL MOMENTO DE LA FALLA (solo con 1 replica viva)"
  awk '$3<2{printf "   bloque %-3s %-22s repl=%s  %s\n",$1,$2,$3,$4; n++} END{if(!n) print "   (la re-replicacion fue mas rapida que el muestreo)"}' "$dur/bloques.txt"
  echo
  echo "TIEMPOS DEL DATASET $ds (desde que se detuvo $nodo)"
  echo "   Paso a STALE                        : ${t_stale:-no registrado} s"
  echo "   Marcado como MUERTO                 : ${t_dead:-no registrado} s"
  echo "   Replicas de $nodo eliminadas del mapa: ${t_rem:-no registrado} s"
  echo "   Re-replicacion completa             : ${t_rec:-no registrado} s"
  [ -n "$t_rem" ] && [ -n "$t_rec" ] && echo "   Duracion de la re-replicacion       : $((t_rec - t_rem)) s"
  echo "   Maximo de bloques sub-replicados del dataset: $max_sub"
  } | tee "$dir/tiempos.txt" | tee -a "$log"

  echo; echo "Tomando el estado DESPUES de la recuperacion..."; echo
  cmd_estado "$ds" despues
  echo; cmd_comparar "$ds"
}

# ---------------------------------------------------------------------
cmd_comparar() {
  ds="$1"; a="$OUT/$ds/antes"; d="$OUT/$ds/despues"; f="$OUT/$ds/comparacion.txt"
  [ -f "$a/bloques.txt" ] && [ -f "$d/bloques.txt" ] || { echo "Falta el estado antes o despues de $ds"; return 1; }
  {
  titulo "DATASET $ds - COMPARACION ANTES / DESPUES DE LA FALLA"
  printf "   %-6s %-12s %-12s %-10s %s\n" "BLOQUE" "ANTES" "DESPUES" "PERDIDA" "NUEVA REPLICA EN"
  awk '
    FNR==NR {antes[$1]=$4; next}
    {
      split(antes[$1],x,","); split($4,y,",")
      perd=""; for(i in x){f=0; for(k in y) if(x[i]==y[k]) f=1; if(!f) perd=perd (perd==""?"":",") x[i]}
      nueva=""; for(k in y){f=0; for(i in x) if(x[i]==y[k]) f=1; if(!f) nueva=nueva (nueva==""?"":",") y[k]}
      if(perd!=""){afect++; split(nueva,z,","); for(m in z) if(z[m]!="") cnt[z[m]]++}
      if(perd!="") printf "   %-6s %-12s %-12s %-10s %s\n",$1,antes[$1],$4,perd,(nueva==""?"-":nueva)
      total++
    }
    END{
      printf "\n   Bloques del archivo         : %d\n", total
      printf "   Bloques afectados por la falla: %d\n", afect
      for(k in cnt) printf "   Nuevas replicas creadas en %s: %d\n", k, cnt[k]
    }' "$a/bloques.txt" "$d/bloques.txt"
  } | tee "$f"
}

# ---------------------------------------------------------------------
cmd_check() {
  j=$(curl -s "$JMX_URL")
  [ -z "$j" ] && { echo "ERROR: no se pudo leer el JMX del NameNode ($JMX_URL)"; return 1; }
  u=$(jmx_val "$j" UnderReplicatedBlocks); [ -z "$u" ] && u=$(jmx_val "$j" LowRedundancyBlocks)
  echo "JMX del NameNode OK -> vivos=$(jmx_val "$j" NumLiveDataNodes) muertos=$(jmx_val "$j" NumDeadDataNodes) stale=$(jmx_val "$j" NumStaleDataNodes) subreplicados=$u"
}

# ---------------------------------------------------------------------
cmd_guardar() {
  hdfs dfs -mkdir -p "/${GRUPO}/resultados"
  hdfs dfs -put -f "$OUT"/* "/${GRUPO}/resultados/"
  hdfs dfs -chown -R sandbox:sandbox "/${GRUPO}/resultados"
  echo "Resultados copiados a HDFS:"; hdfs dfs -ls -R "/${GRUPO}/resultados" | head -40
}

case "${1:-}" in
  estado)   cmd_estado   "${2:?dataset}" "${3:?momento}" ;;
  monitor)  cmd_monitor  "${2:?dataset}" "${3:-DN2}" ;;
  comparar) cmd_comparar "${2:?dataset}" ;;
  guardar)  cmd_guardar ;;
  check)    cmd_check ;;
  *) sed -n '2,15p' "$0" ;;
esac
