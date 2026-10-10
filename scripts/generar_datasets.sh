#!/usr/bin/env bash
# LG15 - GRUPO 01 - Genera un dataset CSV del tamano exacto y lo sube directo a HDFS.
# Cada registro identifica al grupo:  grupo01,0000000001,LG15,registro_de_prueba_hdfs
# Uso (como usuario sandbox):
#   docker compose exec -u sandbox clientnode bash /tmp/lg15/generar_datasets.sh 1GB
#   docker compose exec -u sandbox clientnode bash /tmp/lg15/generar_datasets.sh 10GB
set -e
GRUPO="grupo01"
TAM="${1:?indica 1GB o 10GB}"
case "$TAM" in 1GB) BYTES=1G ;; 10GB) BYTES=10G ;; *) echo "Tamano no valido: $TAM"; exit 1 ;; esac
DESTINO="/${GRUPO}/dataset_${TAM}/dataset_${GRUPO}_${TAM}"
echo "GRUPO 01 - LG15 - generando $DESTINO - $(TZ=UTC+4 date '+%Y-%m-%d %H:%M:%S')"
time (seq -f "${GRUPO},%010.0f,LG15,registro_de_prueba_hdfs" 1 300000000 | head -c "$BYTES" | hdfs dfs -put - "$DESTINO")
hdfs dfs -ls "$DESTINO"
hdfs dfs -du -s -h "$(dirname "$DESTINO")"
hdfs dfs -cat "$DESTINO" 2>/dev/null | head -3
