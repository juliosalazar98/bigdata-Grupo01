#!/usr/bin/env bash
# LG15 - GRUPO 01 - Crea la estructura del grupo en HDFS.
# Ejecutar como administrador de HDFS:
#   docker compose exec -u hdfs clientnode bash /tmp/lg15/preparar_hdfs.sh
set -e
GRUPO="grupo01"
hdfs dfs -mkdir -p /${GRUPO}/dataset_1GB /${GRUPO}/dataset_10GB /${GRUPO}/resultados /${GRUPO}/evidencias
hdfs dfs -chown -R sandbox:sandbox /${GRUPO}
echo "GRUPO 01 - LG15 - $(TZ=UTC+4 date '+%Y-%m-%d %H:%M:%S')"
hdfs dfs -ls -R /${GRUPO}
