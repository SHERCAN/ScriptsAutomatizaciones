# =============================================================================
# windows-port-killer.ps1 — Encuentra y libera puertos en uso en Windows
# =============================================================================
# Propósito: Ayudar a los desarrolladores a encontrar y detener rápidamente
# procesos bloqueados que ocupan puertos (ej. 3000, 5173, 8000, 8080).
# Requiere: Windows PowerShell 5.1+ o PowerShell Core
# Uso: .\windows-port-killer.ps1 -Port 5173
#      .\windows-port-killer.ps1 -Port 8000 -Force
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="El puerto de red que deseas liberar (ej. 5173)")]
    [int]$Port,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

Write-Host "=== Buscando procesos en el puerto $Port ===" -ForegroundColor Cyan

# Obtener conexiones activas en el puerto indicado
$connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue

if (-not $connections) {
    Write-Host "No se encontraron conexiones activas o procesos escuchando en el puerto $Port." -ForegroundColor Green
    Exit 0
}

# Obtener IDs de procesos únicos
$pids = $connections.OwningProcess | Select-Object -Unique

foreach ($pid in $pids) {
    # Evitar matar procesos del sistema esenciales (PID 0, 4, etc.)
    if ($pid -le 4) {
        Write-Host "⚠️ El proceso que usa el puerto $Port es un proceso del sistema (PID: $pid). Omitiendo por seguridad." -ForegroundColor Yellow
        continue
    }

    # Obtener información del proceso
    $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if (-not $process) {
        Write-Host "No se pudo obtener información del proceso con PID: $pid" -ForegroundColor Gray
        continue
    }

    Write-Host "Proceso encontrado:" -ForegroundColor Yellow
    Write-Host "  Nombre: $($process.Name)" -ForegroundColor Yellow
    Write-Host "  PID:    $pid" -ForegroundColor Yellow
    Write-Host "  Ruta:   $($process.Path)" -ForegroundColor Gray

    # Confirmar si se desea terminar el proceso
    if ($Force) {
        $confirm = "Y"
    } else {
        $confirm = Read-Host "¿Deseas terminar este proceso para liberar el puerto? (Y/N)"
    }

    if ($confirm -eq "Y" -or $confirm -eq "y") {
        Write-Host "Deteniendo proceso $($process.Name) (PID: $pid)..." -ForegroundColor Gray
        try {
            Stop-Process -Id $pid -Force -ErrorAction Stop
            Write-Host "✅ Proceso terminado exitosamente. Puerto $Port liberado." -ForegroundColor Green
        }
        catch {
            Write-Error "Error al detener el proceso: $_"
        }
    } else {
        Write-Host "Operación cancelada. El proceso sigue activo." -ForegroundColor Gray
    }
}
