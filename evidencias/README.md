# Evidencias – GRUPO 01 · LG15

Capturas de pantalla de la implementación y de las pruebas. En cada captura de terminal aparece el encabezado **GRUPO 01 - LG15** con fecha y hora.

| Carpeta | Archivo sugerido | Qué muestra |
|---|---|---|
| `01_entorno` | `01_docker_compose_ps.png` | Los 15 contenedores en estado *healthy* (incluye datanode, datanode2 y datanode3) |
| | `02_dfsadmin_report.png` | `hdfs dfsadmin -report`: **Live datanodes (3)** |
| | `03_replicacion_2.png` | `hdfs getconf -confKey dfs.replication` → **2** |
| | `04_web_overview.png` | localhost:9870 · Overview: Live Nodes 3 / Dead Nodes 0 |
| | `05_web_datanodes.png` | localhost:9870 · Datanodes: los 3 nodos *In Service* |
| `02_datasets` | `01_estructura_grupo01.png` | `hdfs dfs -ls -R /grupo01` con las 4 carpetas y el dataset de 1 GB |
| | `02_dataset_10GB.png` | Carga del dataset de 10 GB y `hdfs dfs -du` (10 G / 20 G) |
| `03_prueba_1GB` | `01_antes_A.png`, `01_antes_B.png` | Estado antes de la falla |
| | `02_monitor.png` | Monitoreo de la falla de DN2 (STALE → MUERTO → re-replicación) |
| | `03_web_dn2_muerto.png` | Pestaña Datanodes con DN2 en rojo |
| | `04_subreplicados_tiempos.png` | Bloques con 1 réplica y tiempos |
| | `05_despues.png` | Estado después de la recuperación |
| | `06_comparacion.png` | Qué bloques perdieron réplica y dónde se crearon las nuevas |
| | `07_restaurado.png` | DN2 vuelve y se eliminan las réplicas sobrantes |
| `04_prueba_10GB` | (mismos nombres que la prueba de 1 GB) | |
| `05_hdfs_resultados` | `01_resultados_en_hdfs.png` | `lg15.sh guardar`: resultados copiados a `/grupo01/resultados` |

Las salidas completas en texto de todas las pruebas están en [`../resultados/`](../resultados/).
