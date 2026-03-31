# ==============================================================================
# SCRIPT DE MONITOREO DE DATACENTER - PANACEA - FCAMACHO
# ==============================================================================

# --- CONFIGURACIÓN DE RUTAS ---
$RutaBase  = "C:\BotMonitoreo"
$LogStatus = "$RutaBase\estado.txt"
$LogDebug  = "$RutaBase\chequeo_system.log"

if (-not (Test-Path $RutaBase)) { New-Item -ItemType Directory -Path $RutaBase | Out-Null }

# Test de inicio inmediato para ver si el script arranca
$FechaTest = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
"--- INICIO CHEQUEO: $FechaTest ---" | Out-File $LogDebug -Append

# --- CONFIGURACIÓN DE SEGURIDAD Y DATOS ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Token  = "8542811530:AAHaZjcDSjZFGjcsjDQQz5pN-g-9xIERBfw"
$ChatID = "-1003544338364" 

# Iconos
$emoAlert = [char]::ConvertFromUtf32(0x1F6A8) # 🚨
$emoOk    = [char]::ConvertFromUtf32(0x2705)  # ✅
$emoServ  = [char]::ConvertFromUtf32(0x1F5A5) # 🖥️
$emoSw    = [char]::ConvertFromUtf32(0x1F50C) # 🔌
$emoTime  = [char]::ConvertFromUtf32(0x23F1)  # ⏱️
$emoWorld = [char]::ConvertFromUtf32(0x1F310) # 🌐
$emoGreen = [char]::ConvertFromUtf32(0x1F7E2) # 🟢

# --- FUNCIÓN DE TEST (DEBE IR FUERA DEL CICLO) ---
function Test-EquipoHibrido {
    param($IP, $Puerto)
    try {
        if ($Puerto) {
            $Socket = New-Object System.Net.Sockets.TcpClient
            $Connect = $Socket.BeginConnect($IP, $Puerto, $null, $null)
            $Wait = $Connect.AsyncWaitHandle.WaitOne(2000, $false)
            $Result = $Wait -and $Socket.Connected
            if ($Socket) { $Socket.Dispose() }
            return $Result
        } else {
            return Test-Connection -ComputerName $IP -Count 1 -Quiet
        }
    } catch {
        return $false
    }
}

# --- FUNCIÓN DE ENVÍO ---
function Send-Telegram ($Mensaje) {
    $MensajeSeguro = [Uri]::EscapeDataString($Mensaje)
    $url = "https://api.telegram.org/bot$Token/sendMessage?chat_id=$ChatID&text=$MensajeSeguro&parse_mode=Markdown"
    try {
        $null = Invoke-RestMethod -Uri $url -Method Post
    } catch {
        "Error Telegram: $($_.Exception.Message)" | Out-File $LogDebug -Append
    }
}

# --- LISTA DE EQUIPOS ---
$Equipos = @(
    @{Nombre="Servidor Pc de Lima"; IP="10.10.48.118";    Tipo="SERVIDOR"; Icono=$emoServ},
    @{Nombre="Servidor SERVL009";   IP="192.168.5.15";    Tipo="SERVIDOR"; Icono=$emoServ; Puerto=80}, 
    @{Nombre="GTD_Lima_10Mbps";     IP="172.31.0.113";    Tipo="SWITCH";   Icono=$emoSw},
    @{Nombre="SWChiclayo-P11-1";    IP="192.168.246.250"; Tipo="SWITCH";   Icono=$emoSw}
)

# --- PROCESO ---
if (-not (Test-Path $LogStatus)) { "" | Out-File $LogStatus }
$CaidosAntes = Get-Content $LogStatus | Where-Object { $_ -match "\d" }
$EstadoActual = New-Object System.Collections.Generic.List[string]

foreach ($Dev in $Equipos) {
    # Primer intento
    $EnLinea = Test-EquipoHibrido -IP $Dev.IP -Puerto $Dev.Puerto

    # Reintento si falló
    if (-not $EnLinea) {
        "Fallo inicial en $($Dev.Nombre). Reintentando..." | Out-File $LogDebug -Append
        Start-Sleep -Seconds 5
        $EnLinea = Test-EquipoHibrido -IP $Dev.IP -Puerto $Dev.Puerto
    }

    if (-not $EnLinea) {
        [void]$EstadoActual.Add($Dev.IP)
        if ($Dev.IP -notin $CaidosAntes) {
            $Msg = "$emoAlert *CAIDA DETECTADA*`n"
            $Msg += "$($Dev.Icono) *$($Dev.Tipo):* $($Dev.Nombre)`n"
            $Msg += "$emoWorld *IP:* $($Dev.IP)`n"
            $Msg += "$emoTime *Fecha:* $FechaTest"
            Send-Telegram $Msg
        }
    } else {
        if ($Dev.IP -in $CaidosAntes) {
            $Msg = "$emoOk *RESTABLECIDO*`n"
            $Msg += "$($Dev.Icono) *$($Dev.Tipo):* $($Dev.Nombre)`n"
            $Msg += "$emoGreen *Estado:* En linea`n"
            $Msg += "$emoTime *Fecha:* $FechaTest"
            Send-Telegram $Msg
        }
    }
}

$EstadoActual | Out-File $LogStatus -Force
"--- FIN CHEQUEO ---" | Out-File $LogDebug -Append