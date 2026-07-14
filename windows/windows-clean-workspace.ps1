# =============================================================================
# windows-clean-workspace.ps1 — Limpia directorios de compilación pesados
# =============================================================================
# Propósito: Buscar y eliminar de forma recursiva carpetas pesadas generadas
# por compilaciones (Rust, Node, frontend, etc.) para recuperar espacio en disco.
# Requiere: Windows PowerShell 5.1+ o PowerShell Core
# Uso: Run/Execute inside a development directory to clean it.
#      .\windows-clean-workspace.ps1 -Path "C:\Users\Yesid Farfan\Documents\Proyectos"
#      .\windows-clean-workspace.ps1 -AnalyzeOnly (Only counts files/sizes)
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$Path = ".",

    [Parameter(Mandatory=$false)]
    [switch]$AnalyzeOnly
)

# Convertir a ruta absoluta
$resolvedPath = Resolve-Path $Path
Write-Host "=== Iniciando limpieza en: $($resolvedPath.Path) ===" -ForegroundColor Cyan

# Definir carpetas a buscar (patrones de carpetas de compilación pesadas)
$targets = @("target", "node_modules", ".next", "dist", ".cache", "build")

# Contador de espacio
$totalSpaceSavedBytes = 0
$foldersFound = @()

Write-Host "Escaneando directorios... (esto puede tardar unos momentos)" -ForegroundColor Gray

foreach ($target in $targets) {
    # Buscar carpetas recursivamente
    $items = Get-ChildItem -Path $resolvedPath -Filter $target -Recurse -Directory -ErrorAction SilentlyContinue
    
    foreach ($item in $items) {
        # Evitar borrar cosas fuera del directorio de desarrollo si por error coincide
        # Mostrar el tamaño de la carpeta antes de borrar
        $sizeBytes = 0
        $files = Get-ChildItem -Path $item.FullName -Recurse -File -ErrorAction SilentlyContinue
        if ($files) {
            $sizeBytes = ($files | Measure-Object -Property Length -Sum).Sum
        }
        
        $sizeMB = [Math]::Round($sizeBytes / 1MB, 2)
        Write-Host "Encontrado: $($item.FullName) ($sizeMB MB)" -ForegroundColor Yellow
        
        $foldersFound += [PSCustomObject]@{
            Path = $item.FullName
            Size = $sizeBytes
        }
        $totalSpaceSavedBytes += $sizeBytes
    }
}

$totalSpaceSavedMB = [Math]::Round($totalSpaceSavedBytes / 1MB, 2)
$totalSpaceSavedGB = [Math]::Round($totalSpaceSavedBytes / 1GB, 2)

Write-Host "`n--- Resumen de Análisis ---" -ForegroundColor Cyan
Write-Host "Carpetas encontradas: $($foldersFound.Count)" -ForegroundColor White
Write-Host "Espacio total a liberar: $totalSpaceSavedMB MB ($totalSpaceSavedGB GB)" -ForegroundColor White

if ($foldersFound.Count -eq 0) {
    Write-Host "El workspace ya está limpio. No se requiere acción." -ForegroundColor Green
    Exit 0
}

if ($AnalyzeOnly) {
    Write-Host "Modo análisis. No se eliminó ningún archivo." -ForegroundColor Gray
    Exit 0
}

# Solicitar confirmación
$confirm = Read-Host "¿Estás seguro de que deseas ELIMINAR permanentemente estas carpetas? (Y/N)"
if ($confirm -eq "Y" -or $confirm -eq "y") {
    Write-Host "`nEliminando carpetas..." -ForegroundColor Gray
    foreach ($folder in $foldersFound) {
        try {
            Write-Host "Borrando: $($folder.Path)..." -ForegroundColor Gray
            Remove-Item -Path $folder.Path -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Host "⚠️ Error al eliminar $($folder.Path): $_" -ForegroundColor Red
        }
    }
    Write-Host "`n✅ Limpieza completada exitosamente. Se liberaron $totalSpaceSavedGB GB." -ForegroundColor Green
} else {
    Write-Host "Operación cancelada. No se eliminó ningún archivo." -ForegroundColor Gray
}
