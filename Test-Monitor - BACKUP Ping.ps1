# ==============================================================================
# SCRIPT DE MONITOREO DE DATACENTER - ALERTAS TELEGRAM
# UBICACIÓN: C:\BotMonitoreo\Test-Monitor.ps1
# ==============================================================================

# --- CONFIGURACIÓN DE RUTAS ---
$RutaBase  = "C:\BotMonitoreo"
$LogStatus = "$RutaBase\estado.txt"
$LogDebug  = "$RutaBase\chequeo_system.log"

# Asegurar que la carpeta existe
if (-not (Test-Path $RutaBase)) { New-Item -ItemType Directory -Path $RutaBase | Out-Null }

# Log de ejecución para control del sistema
$FechaTest = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
"El script corrio a las $FechaTest" | Out-File $LogDebug -Append

# --- CONFIGURACIÓN DE SEGURIDAD ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- DATOS DE TELEGRAM ---
$Token  = "8542811530:AAHaZjcDSjZFGjcsjDQQz5pN-g-9xIERBfw"
$ChatID = "-1003544338364" 

# --- ICONOS (USANDO CÓDIGOS UNICODE PARA EVITAR ERRORES) ---
$emoAlert = [char]::ConvertFromUtf32(0x1F6A8) # 🚨
$emoOk    = [char]::ConvertFromUtf32(0x2705)  # ✅
$emoServ  = [char]::ConvertFromUtf32(0x1F5A5) # 🖥️
$emoSw    = [char]::ConvertFromUtf32(0x1F50C) # 🔌
$emoTime  = [char]::ConvertFromUtf32(0x23F1)  # ⏱️
$emoWorld = [char]::ConvertFromUtf32(0x1F310) # 🌐
$emoGreen = [char]::ConvertFromUtf32(0x1F7E2) # 🟢

# --- LISTA DE EQUIPOS A MONITOREAR ---
$Equipos = @(
    @{Nombre="Servidor Pc de Lima";      IP="10.10.48.118";    Tipo="SERVIDOR"; Icono=$emoServ},
    @{Nombre="Servidor SERVL009";        IP="192.168.5.15";    Tipo="SERVIDOR"; Icono=$emoServ},
    @{Nombre="GTD_Lima_10Mbps";          IP="172.31.0.113";    Tipo="SWITCH";   Icono=$emoSw},
    @{Nombre="SWChiclayo-P11-1";         IP="192.168.246.267"; Tipo="SWITCH";   Icono=$emoSw}
)

# --- FUNCIÓN DE ENVÍO A TELEGRAM ---
function Send-Telegram ($Mensaje) {
    # Forzamos la codificación UTF8 para evitar símbolos extraños
    $MensajeSeguro = [Uri]::EscapeDataString($Mensaje)
    $url = "https://api.telegram.org/bot$Token/sendMessage?chat_id=$ChatID&text=$MensajeSeguro&parse_mode=Markdown"
    try {
        $null = Invoke-RestMethod -Uri $url -Method Post
    } catch {
        "Error Telegram: $($_.Exception.Message)" | Out-File "$RutaBase\error_ejecucion.txt" -Append
    }
}

# --- PROCESO DE MONITOREO ---
if (-not (Test-Path $LogStatus)) { "" | Out-File $LogStatus }

# Leemos IPs que ya estaban caídas
$CaidosAntes = Get-Content $LogStatus | Where-Object { $_ -match "\d" }
$EstadoActual = New-Object System.Collections.Generic.List[string]

foreach ($Dev in $Equipos) {
    $MomentoEvento = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    
    # Realizamos el Ping (2 intentos para evitar falsos positivos)
    $Ping = Test-Connection -ComputerName $Dev.IP -Count 2 -Quiet
    
    if (-not $Ping) {
        # --- EQUIPO CAÍDO ---
        [void]$EstadoActual.Add($Dev.IP)
        
        if ($Dev.IP -notin $CaidosAntes) {
            $Msg = "$emoAlert *CAIDA DETECTADA*`n"
            $Msg += "$($Dev.Icono) *$($Dev.Tipo):* $($Dev.Nombre)`n"
            $Msg += "$emoWorld *IP:* $($Dev.IP)`n"
            $Msg += "$emoTime *Fecha/Hora:* $MomentoEvento"
            Send-Telegram $Msg
        }
    } else {
        # --- EQUIPO OK ---
        if ($Dev.IP -in $CaidosAntes) {
            $Msg = "$emoOk *EQUIPO RESTABLECIDO*`n"
            $Msg += "$($Dev.Icono) *$($Dev.Tipo):* $($Dev.Nombre)`n"
            $Msg += "$emoGreen *Estado:* En linea nuevamente`n"
            $Msg += "$emoTime *Fecha/Hora:* $MomentoEvento"
            Send-Telegram $Msg
        }
    }
}

# Guardamos el estado actual para la siguiente vuelta
$EstadoActual | Out-File $LogStatus -Force