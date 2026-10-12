# Tolerancia a fallos y replicación de datos en HDFS

Práctica **LG15 · Grupo 01**. Se desplegó un clúster Hadoop HDFS con Docker Compose y se realizaron dos pruebas con datasets de **1 GB y 10 GB**, deteniendo un DataNode en cada experimento. Ambos archivos permanecieron disponibles y HDFS recuperó automáticamente sus réplicas.

## Contenido

- [Arquitectura y configuración](#1-arquitectura-y-configuración)
- [Instalación y preparación](#2-instalación-y-preparación)
- [Pruebas de fallo](#3-pruebas-de-fallo)
- [Comparación y análisis](#4-comparación-y-análisis)
- [Evidencias](#5-evidencias)
- [Preguntas](#6-preguntas)
- [Conclusiones](#7-conclusiones)
- [Informe completo](#informe-completo)

## Integrantes

- Edson Marcelo Cayo Ali
- Joel Julio Salazar Ferrufino
- Alex Bryam Barrera Alarcon

**Universidad Privada del Valle · Tecnologías Emergentes I · Grupo B · Gestión 2/2026**

**Docente:** Ing. Efrain Luna Mamani.

## 1. Arquitectura y configuración

El entorno se basa en Hadoop Sandbox, ampliado con dos DataNodes adicionales en [docker-compose.yaml](docker-compose.yaml). El NameNode administra los metadatos y la ubicación de los bloques; los DataNodes almacenan los datos y sus réplicas.

| Componente | Configuración utilizada |
| --- | --- |
| NameNode | 1, servicio `namenode` |
| DataNodes | 3: `datanode` (DN1, hostname `hadoopnode`), `datanode2` (DN2) y `datanode3` (DN3) |
| Nodo cliente | `clientnode`, usuario `sandbox` |
| Factor de replicación | 2 |
| Tamaño de bloque | 128 MiB |
| Datasets | 1.000.000.000 y 10.000.000.000 bytes, generados con `/dev/zero` |
| Directorio HDFS | `/grupo01` |

La propiedad `dfs.replication` está configurada en `2` en [conf/hadoop/hdfs-site.xml](conf/hadoop/hdfs-site.xml). El Compose conserva los servicios complementarios de Hadoop Sandbox; estas pruebas se centran en HDFS.

### Diagrama de arquitectura

```mermaid
flowchart LR
    subgraph DC["Docker Compose - Hadoop Sandbox Grupo 01"]
        Client["clientnode<br/>Cliente Hadoop/Spark<br/>SSH: 2222"]

        subgraph HDFS["HDFS - Replicación 2"]
            NN["namenode<br/>UI: 9870"]
            DN1["datanode<br/>DN1"]
            DN2["datanode2<br/>DN2"]
            DN3["datanode3<br/>DN3"]
        end

        subgraph YARN["YARN"]
            RM["resourcemanager<br/>UI: 8088"]
            NM["nodemanager<br/>UI: 8042"]
        end

        subgraph History["Historial"]
            JHS["jobhistoryserver<br/>UI: 19888"]
            SHS["sparkhistoryserver<br/>UI: 18080"]
        end

        JMX["5 JMX Exporters<br/>Monitoreo de servicios"]
        Front["front - Apache HTTPD<br/>UI: 8080<br/>Proxy web"]
    end

    Client -->|Comandos HDFS| NN
    Client -->|Trabajos YARN/Spark| RM

    NN <-->|Heartbeats y reportes| DN1
    NN <-->|Heartbeats y reportes| DN2
    NN <-->|Heartbeats y reportes| DN3

    RM -->|Coordina recursos| NM

    NN --> JHS
    RM --> JHS
    NN --> SHS
    RM --> SHS

    NN -.-> JMX
    DN1 -.-> JMX
    RM -.-> JMX
    NM -.-> JMX
    JHS -.-> JMX

    Front --> NN
    Front --> DN1
    Front --> RM
    Front --> NM
    Front --> JHS
    Front --> SHS
```

## 2. Instalación y preparación

Se requiere Git y Docker con Docker Compose y soporte para contenedores Linux. Desde la terminal del host:

```powershell
git clone https://github.com/juliosalazar98/bigdata-Grupo01.git
cd bigdata-Grupo01
docker compose up -d
```

Con el clúster iniciado, verificar los DataNodes y preparar el directorio del grupo:

```powershell
docker compose exec -u hdfs namenode hdfs dfsadmin -report
docker compose exec -u hdfs namenode hdfs dfs -mkdir -p /grupo01
docker compose exec -u hdfs namenode hdfs dfs -chown sandbox:sandbox /grupo01
```

Ingresar al nodo cliente:

```powershell
docker compose exec -u sandbox clientnode bash
```

Dentro de esa sesión Bash, comprobar que el factor de replicación devuelve `2` y definir las rutas:

```bash
hdfs getconf -confKey dfs.replication
BASE=/grupo01
F1="$BASE/dataset_1GB/dataset_grupo01_1GB"
F10="$BASE/dataset_10GB/dataset_grupo01_10GB"
hdfs dfs -mkdir -p "$BASE/dataset_1GB" "$BASE/dataset_10GB"
hdfs dfs -ls "$BASE"
```

> [!IMPORTANT]
> Ejecutar los comandos `docker compose` desde el host, en la raíz del repositorio, conservando la carpeta `conf/`. Los comandos `hdfs` y `head` de las pruebas se ejecutan dentro del nodo cliente. Mantener esa sesión para conservar las variables `BASE`, `F1` y `F10`; usar otra terminal del host para detener y reiniciar los DataNodes.

La interfaz del NameNode está disponible en [localhost:9870](http://localhost:9870) y los archivos pueden consultarse en el [explorador HDFS](http://localhost:9870/explorer.html#/grupo01).

## 3. Pruebas de fallo

### 3.1. Dataset de 1 GB

**Carga y estado inicial — nodo cliente:**

```bash
head -c 1000000000 /dev/zero | hdfs dfs -put - "$F1"
hdfs dfs -ls -h "$F1"
hdfs dfs -stat 'Tamaño: %b bytes | Replicacion: %r' "$F1"
hdfs fsck "$F1" -files -blocks -locations
```

El archivo presentó **8 bloques con dos réplicas**, tres DataNodes activos y estado `HEALTHY`.

**Simulación de fallo — host:**

```powershell
docker compose stop datanode2
```

**Disponibilidad, lectura y bloques — nodo cliente:**

```bash
hdfs dfs -test -e "$F1" && echo "Archivo disponible"
hdfs dfs -cat "$F1" > /dev/null && echo "Lectura correcta"
hdfs fsck "$F1" -files -blocks -locations
```

DN2 almacenaba cuatro bloques del archivo. Durante la comprobación se observaron **3 bloques subreplicados (37,5 %)**: uno de los cuatro afectados ya había recuperado su segunda réplica. Los ocho bloques continuaron disponibles y la lectura fue correcta.

**Recuperación — nodo cliente:** repetir la comprobación antes de reiniciar DN2.

```bash
hdfs fsck "$F1" -files -blocks -locations
```

El registro posterior mostró dos réplicas por bloque y cero bloques subreplicados, utilizando DN1 y DN3. Finalmente, desde el host:

```powershell
docker compose start datanode2
```

### 3.2. Dataset de 10 GB

Con los tres DataNodes nuevamente activos, realizar la segunda prueba.

**Carga y estado inicial — nodo cliente:**

```bash
head -c 10000000000 /dev/zero | hdfs dfs -put - "$F10"
hdfs dfs -ls -h "$F10"
hdfs dfs -stat 'Tamaño: %b bytes | Replicacion: %r' "$F10"
hdfs fsck "$F10" -files -blocks -locations
```

El archivo presentó **75 bloques con dos réplicas** y estado `HEALTHY`.

**Simulación de fallo — host:**

```powershell
docker compose stop datanode3
```

**Disponibilidad, lectura y bloques — nodo cliente:**

```bash
hdfs dfs -test -e "$F10" && echo "Archivo disponible"
hdfs dfs -cat "$F10" > /dev/null && echo "Lectura correcta"
hdfs fsck "$F10" -files -blocks -locations
```

DN3 almacenaba 57 bloques del archivo. Durante la comprobación se observaron **45 bloques subreplicados (60 %)**; los otros 12 afectados ya habían recuperado su segunda réplica. Los 75 bloques permanecieron disponibles y la lectura fue correcta.

**Recuperación — nodo cliente:** repetir la comprobación antes de reiniciar DN3.

```bash
hdfs fsck "$F10" -files -blocks -locations
```

El registro posterior mostró dos réplicas por bloque y cero bloques subreplicados, utilizando DN1 y DN2. Finalmente, desde el host:

```powershell
docker compose start datanode3
```

### 3.3. Verificación final

Desde el nodo cliente, consultar los directorios, el espacio utilizado y la integridad de ambos archivos:

```bash
hdfs dfs -ls -R "$BASE"
hdfs dfs -du -h "$BASE"
hdfs fsck "$BASE"
```

La verificación final de `/grupo01` mostró **dos archivos, 83 bloques, tres DataNodes y estado `HEALTHY`**, sin bloques perdidos, corruptos ni subreplicados.

## 4. Comparación y análisis

| Característica | Dataset 1 GB | Dataset 10 GB |
| --- | --- | --- |
| Tamaño | 1.000.000.000 bytes | 10.000.000.000 bytes |
| Número de bloques | 8 | 75 |
| Tamaño de bloque | 128 MiB | 128 MiB |
| Factor de replicación | 2 | 2 |
| Distribución inicial de réplicas | DN1: 7 · DN2: 4 · DN3: 5 | DN1: 42 · DN2: 51 · DN3: 57 |
| DataNode detenido | DN2 | DN3 |
| Bloques inicialmente afectados | 4 | 57 |
| Bloques subreplicados observados | 3 (37,5 %) | 45 (60 %) |
| Bloques disponibles durante la falla | 8 de 8 | 75 de 75 |
| Archivo accesible y lectura correcta | Sí | Sí |
| Bloques perdidos o corruptos | 0 | 0 |
| Nuevas réplicas | 4, en DN1 y DN3 | 57, en DN1 y DN2 |
| Subreplicados tras la recuperación | 0 | 0 |
| Tiempo de recuperación | 121,87 s (2 min 1,87 s), incluida la detección del fallo | 140,28 s (2 min 20,28 s), incluida la detección del fallo |
| Estado final | `HEALTHY` | `HEALTHY` |

**Antes de la falla**, cada bloque tenía dos copias en nodos diferentes. **Durante la falla**, las réplicas restantes permitieron leer los archivos completos. **Después**, el NameNode coordinó la creación de nuevas copias en los nodos disponibles, recuperando el factor de replicación incluso mientras el nodo detenido seguía fuera de servicio.

El dataset de 10 GB permitió observar una distribución más amplia y la recuperación de más réplicas. Las cifras de subreplicación corresponden al momento de cada consulta, cuando parte de la recuperación ya había ocurrido.

> [!NOTE]
> Disponibilidad y replicación completa son condiciones distintas: los archivos conservaron el estado `HEALTHY` durante la falla, aunque algunos bloques tenían una sola réplica activa. Los tiempos de ejecución de `fsck` no representan el tiempo de recuperación del clúster.

### Registros de resultados

Los `.txt` permiten revisar los identificadores de bloques, sus ubicaciones y las réplicas activas; los archivos de lectura registran la confirmación obtenida durante la falla.

| Dataset | Estado inicial | Durante la falla | Lectura | Recuperación |
| --- | --- | --- | --- | --- |
| 1 GB | [Antes](resultados/1GB_antes.txt) | [Durante](resultados/1GB_durante_falla.txt) | [Lectura](resultados/1GB_lectura.txt) | [Recuperación](resultados/1GB_recuperacion.txt) |
| 10 GB | [Antes](resultados/10GB_antes.txt) | [Durante](resultados/10GB_durante_falla.txt) | [Lectura](resultados/10GB_lectura.txt) | [Recuperación](resultados/10GB_recuperacion.txt) |

## 5. Evidencias

### Entorno y configuración

**01. Contenedores activos.** Docker Compose muestra el NameNode y los tres DataNodes en ejecución, junto con los servicios complementarios.

![Contenedores del clúster activos](evidencias/01_contenedores_activos.png)

**02. Factor de replicación.** El archivo `hdfs-site.xml` establece `dfs.replication` en `2`.

![Configuración del factor de replicación en 2](evidencias/02_factor_replicacion.png)

**03. Estado general de HDFS.** La interfaz del NameNode muestra tres nodos activos, ninguno muerto y cero bloques subreplicados en la consulta capturada.

![Estado general del clúster HDFS](evidencias/03_estado_inicial_hdfs.png)

**04. Tres DataNodes activos.** Se identifican `hadoopnode`, `datanode2` y `datanode3`, con sus direcciones y almacenamiento utilizado.

![Listado de los tres DataNodes](evidencias/04_tres_datanodes_activos.png)

**05. Directorios del Grupo 01.** El explorador HDFS muestra `dataset_1GB` y `dataset_10GB` dentro de `/grupo01`.

![Directorios HDFS del Grupo 01](evidencias/05_directorios_grupo01.png)

### Experimento con 1 GB

**06. Archivo cargado.** `dataset_grupo01_1GB` aparece en HDFS con replicación 2 y bloques de 128 MiB.

![Dataset de 1 GB almacenado en HDFS](evidencias/06_1GB_archivo_cargado.png)

**07. Bloques antes del fallo.** El registro inicial muestra ocho bloques, promedio de dos réplicas y cero subreplicados.

![Estado inicial de los bloques de 1 GB](evidencias/07_1GB_bloques_antes.png)

**08. DataNode 2 detenido.** Docker muestra `datanode2` en estado `Exited`, mientras los demás servicios permanecen iniciados.

![DataNode 2 detenido en Docker](evidencias/08_1GB_datanode2_detenido.png)

**09. Fallo reconocido por HDFS.** La interfaz identifica DN2 como inactivo y mantiene dos DataNodes en operación.

![DataNode 2 inactivo en HDFS](evidencias/09_1GB_nodo_inactivo.png)

**10. Subreplicación durante el fallo.** Se registran tres bloques subreplicados (37,5 %), sin bloques perdidos ni corruptos.

![Bloques del dataset de 1 GB durante la falla](evidencias/10_1GB_bloques_durante_falla.png)

**11. Lectura correcta.** Los comandos confirman la existencia del archivo y su lectura completa durante la falla.

![Disponibilidad y lectura del dataset de 1 GB](evidencias/11_1GB_lectura_correcta.png)

**12. Réplicas recuperadas.** Con solo dos DataNodes activos, el promedio vuelve a dos réplicas y la subreplicación baja a cero.

![Recuperación de réplicas del dataset de 1 GB](evidencias/12_1GB_recuperacion.png)

### Experimento con 10 GB

**13. Archivo cargado.** `dataset_grupo01_10GB` aparece en HDFS con replicación 2 y bloques de 128 MiB.

![Dataset de 10 GB almacenado en HDFS](evidencias/13_10GB_archivo_cargado.png)

**14. Bloques antes del fallo.** El registro inicial muestra 75 bloques, tres DataNodes y dos réplicas por bloque.

![Estado inicial de los bloques de 10 GB](evidencias/14_10GB_bloques_antes.png)

**15. DataNode 3 detenido.** Docker muestra `datanode3` en estado `Exited` para la segunda prueba.

![DataNode 3 detenido en Docker](evidencias/15_10GB_datanode3_detenido.png)

**16. Fallo reconocido por HDFS.** DN3 figura como inactivo; DN1 y DN2 continúan en operación.

![DataNode 3 inactivo en HDFS](evidencias/16_10GB_nodo_inactivo.png)

**17. Subreplicación durante el fallo.** Se observan 45 bloques subreplicados (60 %), sin bloques perdidos ni corruptos.

![Bloques del dataset de 10 GB durante la falla](evidencias/17_10GB_bloques_durante_falla.png)

**18. Lectura correcta.** El archivo continúa disponible y se lee completamente durante la caída de DN3.

![Disponibilidad y lectura del dataset de 10 GB](evidencias/18_10GB_lectura_correcta.png)

**19. Réplicas recuperadas.** HDFS vuelve a registrar dos réplicas por bloque y cero subreplicados con dos DataNodes activos.

![Recuperación de réplicas del dataset de 10 GB](evidencias/19_10GB_recuperacion.png)

### Verificación final

**20. Integridad de ambos datasets.** La revisión de `/grupo01` confirma 83 bloques, tres DataNodes y estado `HEALTHY`, sin bloques subreplicados, perdidos ni corruptos.

![Verificación final de HDFS para el Grupo 01](evidencias/20_verificacion_final_hdfs.png)

## 6. Preguntas

**1. ¿Por qué HDFS mantiene disponible el archivo cuando falla un DataNode?**

Porque cada bloque tiene réplicas almacenadas en otros DataNodes, permitiendo recuperar la información desde las copias disponibles.

**2. ¿Qué ocurriría con un factor de replicación de 1?**

Los bloques almacenados únicamente en el DataNode que falló dejarían de estar disponibles hasta recuperar ese nodo.

**3. ¿Qué sucedería si fallaran dos DataNodes simultáneamente?**

Podrían quedar bloques sin ninguna réplica disponible, provocando que algunos archivos no pudieran leerse completamente.

**4. ¿Por qué replicación 2 no significa dos archivos completos en dos DataNodes?**

Porque HDFS replica individualmente los bloques, que pueden distribuirse entre distintos DataNodes.

**5. ¿Qué relación existe entre tamaño de bloque y número de bloques?**

Para un archivo de tamaño fijo, cuanto menor sea el tamaño de bloque, mayor será la cantidad de bloques necesarios. Por el contrario, un tamaño de bloque mayor genera menos bloques.

**6. ¿Por qué 10 GB representa mejor un sistema distribuido?**

Porque el dataset de 10 GB contiene 75 bloques, mientras que el de 1 GB contiene únicamente 8. Esto permite observar una mayor distribución de datos y un proceso de recuperación más amplio ante la falla de un DataNode.

**7. ¿Qué sucede con los bloques del DataNode que falló?**

HDFS detecta los bloques subreplicados y utiliza las copias disponibles para generar nuevas réplicas en otros DataNodes, restableciendo el factor de replicación configurado.

**8. ¿Quién administra la ubicación y replicación de los bloques?**

El NameNode, que mantiene los metadatos del sistema y coordina la replicación.

**9. ¿Qué diferencia hay entre disponibilidad y cumplimiento del factor de replicación?**

Un archivo puede continuar disponible con una sola réplica de cada bloque, aunque temporalmente no cumpla el factor de replicación configurado.

## 7. Conclusiones

Las pruebas con datasets de 1 GB y 10 GB demostraron que la replicación de bloques permitió mantener los archivos disponibles y leerlos completamente ante la caída de un DataNode. En ambos experimentos, las copias almacenadas en los nodos restantes evitaron la pérdida de acceso a los datos.

Durante las verificaciones se observaron **3 de 8 bloques subreplicados** en el dataset de 1 GB y **45 de 75** en el de 10 GB, sin bloques perdidos ni corruptos. Los archivos conservaron el estado `HEALTHY`, lo que evidencia que su disponibilidad puede mantenerse aunque temporalmente no se cumpla el factor de replicación de 2.

HDFS recuperó automáticamente las réplicas utilizando los DataNodes disponibles, incluso antes de reiniciar el nodo detenido. Las comprobaciones posteriores mostraron dos réplicas por bloque y cero bloques subreplicados; la verificación final confirmó la integridad de los 83 bloques de ambos archivos.

El dataset de 10 GB permitió observar una recuperación de mayor alcance: requirió 57 nuevas réplicas frente a las cuatro del dataset de 1 GB. Estos resultados muestran cómo HDFS conserva la disponibilidad y restablece la redundancia cuando existen réplicas accesibles y nodos disponibles con capacidad suficiente.

## Informe completo

[Consultar el informe completo en PDF](<docs/LG15 – Tolerancia a fallos y replicación de datos en HDFS.pdf>), con el desarrollo de la práctica y las preguntas para la exposición.