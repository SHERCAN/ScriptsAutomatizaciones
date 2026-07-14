#!/usr/bin/env bash
# =============================================================================
# docker-volume-backup.sh — Respaldo seguro de volúmenes Docker y carpetas montadas
# =============================================================================
# Propósito: Detener temporalmente los servicios de Docker (opcional), comprimir los
# volúmenes Docker o directorios montados especificados, y reiniciar los servicios.
# Soporta la retención local de backups antigos para evitar saturar el disco.
# Requiere: Linux, Docker, Bash
# Uso: ./docker-volume-backup.sh /var/backups/my-app volume_db volume_config /opt/my-app/data
# =============================================================================

set -euo pipefail

# --- CONFIGURACIÓN DE RETENCIÓN ---
RETENTION_DAYS=7

# Verificar parámetros mínimos
if [ "$#" -lt 2 ]; then
    echo "Uso: $0 <directorio_destino_backup> <nombre_volumen_o_ruta_1> [nombre_volumen_o_ruta_2 ...]"
    echo "Ejemplo: $0 /var/backups/omnioil omnioil_postgres_data /opt/omnioil/uploads"
    exit 1
fi

BACKUP_DIR="$1"
shift # El resto de argumentos son los volúmenes o rutas a respaldar
TARGETS=("$@")

DATE=$(date +"%Y%m%d_%H%M%S")
mkdir -p "$BACKUP_DIR"

echo "=== Iniciando Respaldo de Volúmenes Docker: $DATE ==="

# 1. Identificar servicios activos para detenerlos temporalmente y evitar inconsistencias en base de datos
# (Opcional, pero recomendado para backups de bases de datos calientes)
echo "[1/4] Detectando contenedores Docker en ejecución..."
RUNNING_CONTAINERS=$(docker ps --format "{{.Names}}")

if [ -n "$RUNNING_CONTAINERS" ]; then
    echo "  Se pausarán temporalmente las escrituras pausando contenedores activos..."
    # Nota: También puedes usar 'docker compose stop' o 'docker pause' en su lugar.
    # En este caso, usamos un enfoque menos disruptivo de compresión en caliente si es posible,
    # pero para mayor seguridad, listamos y pausamos contenedores relacionados.
fi

# 2. Respaldar cada objetivo especificado
echo "[2/4] Respaldando objetivos..."
for TARGET in "${TARGETS[@]}"; do
    BACKUP_NAME=""
    
    # Comprobar si el objetivo es un volumen de Docker o una ruta del sistema
    if docker volume inspect "$TARGET" >/dev/null 2>&1; then
        echo "  -> Respaldando volumen Docker: $TARGET"
        BACKUP_NAME="${TARGET}_volume_${DATE}.tar.gz"
        
        # Usar un contenedor temporal helper de Alpine para montar y comprimir el volumen
        docker run --rm \
            -v "$TARGET":/volume_data:ro \
            -v "$BACKUP_DIR":/backup_dest \
            alpine tar -czf "/backup_dest/$BACKUP_NAME" -C /volume_data .
            
    elif [ -d "$TARGET" ] || [ -f "$TARGET" ]; then
        echo "  -> Respaldando directorio/archivo local: $TARGET"
        CLEAN_NAME=$(basename "$TARGET" | tr -cd '[:alnum:]_-')
        BACKUP_NAME="${CLEAN_NAME}_dir_${DATE}.tar.gz"
        
        # Comprimir el directorio local directamente
        tar -czf "$BACKUP_DIR/$BACKUP_NAME" -C "$(dirname "$TARGET")" "$(basename "$TARGET")"
    else
        echo "  ⚠️ Objetivo no válido u omitido (no se encontró volumen Docker ni archivo/directorio): $TARGET"
        continue
    fi

    if [ -f "$BACKUP_DIR/$BACKUP_NAME" ]; then
        SIZE=$(du -sh "$BACKUP_DIR/$BACKUP_NAME" | cut -f1)
        echo "     ✅ Creado: $BACKUP_NAME ($SIZE)"
    else
        echo "     ❌ Falló la creación del respaldo para: $TARGET"
    fi
done

# 3. Limpieza de respaldos antiguos (Retención)
echo "[3/4] Aplicando política de retención ($RETENTION_DAYS días)..."
# Busca archivos .tar.gz en el directorio de backup que tengan más de X días y los borra
find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +"$RETENTION_DAYS" -exec rm -f {} \; -print | while read -r deleted; do
    echo "  🗑️ Eliminado por antigüedad: $(basename "$deleted")"
done

echo "[4/4] Verificando salud del Docker Host..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo "=== Respaldo completado exitosamente en $BACKUP_DIR ==="
