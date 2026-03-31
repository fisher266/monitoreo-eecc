# ==============================================================================
# SCRIPT DE MONITOREO DE DATACENTER - PANACEA - FCAMACHO (v26.0)
# ==============================================================================

# --- 1. CONFIGURACIÓN DE RUTAS ---
$RutaBase  = "C:\BotMonitoreo"
$LogStatus = "$RutaBase\estado.txt"
$LogDebug  = "$RutaBase\chequeo_system.log"
$HtmlFile  = "$RutaBase\dashboard.html"
$Wkhtml    = "$RutaBase\wkhtmltoimage.exe"
$ImgFile   = "$RutaBase\dashboard.png"

if (-not (Test-Path $RutaBase)) { New-Item -ItemType Directory -Path $RutaBase | Out-Null }

# Limpieza inicial para evitar "fantasmas" de IPs viejas
if (Test-Path $LogStatus) { Remove-Item $LogStatus -Force }
" " | Out-File $LogStatus -Encoding utf8

# --- 2. CONFIGURACIÓN DE TELEGRAM ---
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

# --- 3. FUNCIONES ---

function Test-EquipoHibrido {
    param($IP, $Puerto)
    try {
        if ($Puerto) {
            $Socket = New-Object System.Net.Sockets.TcpClient
            $Connect = $Socket.BeginConnect($IP, $Puerto, $null, $null)
            $Wait = $Connect.AsyncWaitHandle.WaitOne(2500, $false)
            $Result = $Wait -and $Socket.Connected
            if ($Socket) { $Socket.Dispose() }
            return $Result
        } else {
            return Test-Connection -ComputerName $IP -Count 1 -Quiet
        }
    } catch { return $false }
}

function Send-Telegram ($Mensaje) {
    $MensajeSeguro = [Uri]::EscapeDataString($Mensaje)
    $url = "https://api.telegram.org/bot$Token/sendMessage?chat_id=$ChatID&text=$MensajeSeguro&parse_mode=Markdown"
    try { Invoke-RestMethod -Uri $url -Method Post | Out-Null } catch {
        "Error Telegram: $($_.Exception.Message)" | Out-File $LogDebug -Append
    }
}

function Generar-Dashboard ($Resultados) {
    # Usamos entidades HTML para asegurar compatibilidad total
    $HtmlBody = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="10">
    <style>
        @keyframes blink { 0% { opacity: 1; } 50% { opacity: 0.4; } 100% { opacity: 1; } }
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #050505; color: #e0e0e0; padding: 20px; margin: 0; }
        .card { background: #111; border: 1px solid #333; border-radius: 12px; padding: 25px; width: 950px; margin: 20px auto; box-shadow: 0 0 20px rgba(0,255,0,0.1); }
        h1 { color: #2ecc71; text-align: center; font-size: 26px; margin-bottom: 5px; letter-spacing: 1px; }
        p.subtitle { text-align: center; color: #555; font-size: 14px; margin-bottom: 30px; text-transform: uppercase; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; background: #161616; border-radius: 8px; overflow: hidden; }
        th { text-align: left; padding: 15px; background: #222; color: #aaa; font-size: 11px; letter-spacing: 1px; }
        td { padding: 15px; border-bottom: 1px solid #222; font-size: 14px; }
        .status-pill { padding: 6px 12px; border-radius: 4px; font-weight: bold; font-size: 10px; color: white; text-transform: uppercase; display: inline-block; min-width: 60px; text-align: center; }
        .online { background: #27ae60; }
        .offline { background: #c0392b; animation: blink 1s infinite; }
        .time-fail { color: #e74c3c; font-family: monospace; font-weight: bold; }
        .footer { text-align: right; font-size: 11px; color: #444; margin-top: 20px; font-style: italic; }
    </style>
</head>
<body>
    <div class="card">
        <h1>PANACEA - MONITOREO DATACENTER EECC</h1>
        <p class="subtitle">Infraestructura Cr&iacute;tica - Actualizaci&oacute;n en Tiempo Real</p>
        <table>
            <tr>
                <th>DISPOSITIVO</th>
                <th>DIRECCI&Oacute;N IP</th>
                <th>ESTADO</th>
                <th>ULTIMA CA&Iacute;DA / REPORTE</th>
            </tr>
            $(foreach ($r in $Resultados) {
                $clase = if($r.Estado -eq "ONLINE"){"online"}else{"offline"}
                # Si está offline, capturamos el momento exacto
                $fechaCaida = if($r.Estado -eq "OFFLINE"){ Get-Date -Format "dd/MM HH:mm:ss" } else { "<span style='color:#444;'>---</span>" }
                $styleTime = if($r.Estado -eq "OFFLINE"){"class='time-fail'"}else{""}

                "<tr>
                    <td style='font-weight:600;'>$($r.Nombre)</td>
                    <td style='color:#888; font-family:monospace;'>$($r.IP)</td>
                    <td><span class='status-pill $clase'>$($r.Estado)</span></td>
                    <td $styleTime>$fechaCaida</td>
                </tr>"
            })
        </table>
        <div class="footer">
            &Uacute;ltima sincronizaci&oacute;n: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
        </div>
    </div>
</body>
</html>
"@

    # Guardado compatible con tildes
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($HtmlFile, $HtmlBody, $Utf8NoBom)
}
# --- 4. LISTA DE EQUIPOS ---
$Equipos = @(
    @{Nombre="Servidor Pc de Lima"; IP="10.10.48.118";    Tipo="SERVIDOR"; Icono=$emoServ},
    @{Nombre="Servidor SERVL009";   IP="192.168.5.15";    Tipo="SERVIDOR"; Icono=$emoServ; Puerto=80}, 
    @{Nombre="GTD_Lima_10Mbps";     IP="172.31.0.113";    Tipo="SWITCH";   Icono=$emoSw},
    @{Nombre="FW_EL_COMERCIO_LIMA";     IP="172.20.1.1";    Tipo="SWITCH";   Icono=$emoSw},
    @{Nombre="SWArequipa-P11-2";     IP="192.168.153.249";    Tipo="SWITCH";   Icono=$emoSw},
    @{Nombre="SWChiclayo-P11-1";    IP="192.168.246.250"; Tipo="SWITCH";   Icono=$emoSw}

)

# --- 5. BUCLE PRINCIPAL ---
$Offset = 0
Write-Host ">>> MONITOR PANACEA v26.0 ACTIVO <<<" -ForegroundColor Green

while($true) {
    $FechaTest = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    
    # Leer historial de caidos
    if (-not (Test-Path $LogStatus)) { " " | Out-File $LogStatus }
    $CaidosAntes = Get-Content $LogStatus | Where-Object { $_ -match "\d" }
    
    $EstadoActual = New-Object System.Collections.Generic.List[string]
    $ResultadosParaDashboard = New-Object System.Collections.Generic.List[PSObject]

    foreach ($Dev in $Equipos) {
        # Test con Reintento (Tu logica)
        $EnLinea = Test-EquipoHibrido -IP $Dev.IP -Puerto $Dev.Puerto
        if (-not $EnLinea) {
            Start-Sleep -Seconds 4
            $EnLinea = Test-EquipoHibrido -IP $Dev.IP -Puerto $Dev.Puerto
        }

        # Guardar para el Dashboard HTML
        $Res = [PSCustomObject]@{Nombre=$Dev.Nombre; IP=$Dev.IP; Estado=if($EnLinea){"ONLINE"}else{"OFFLINE"}}
        $ResultadosParaDashboard.Add($Res)

        # Logica de Alertas (Tu logica funcional)
        if (-not $EnLinea) {
            [void]$EstadoActual.Add($Dev.IP)
            if ($Dev.IP -notin $CaidosAntes) {
                $Msg = "$emoAlert *CAIDA DETECTADA*`n$($Dev.Icono) *$($Dev.Tipo):* $($Dev.Nombre)`n$emoWorld *IP:* $($Dev.IP)`n$emoTime *Fecha:* $FechaTest"
                Send-Telegram $Msg
                Write-Host "[-] OFFLINE: $($Dev.Nombre)" -ForegroundColor Red
            }
        } else {
            if ($Dev.IP -in $CaidosAntes) {
                $Msg = "$emoOk *RESTABLECIDO*`n$($Dev.Icono) *$($Dev.Tipo):* $($Dev.Nombre)`n$emoGreen *Estado:* En linea`n$emoTime *Fecha:* $FechaTest"
                Send-Telegram $Msg
                Write-Host "[+] ONLINE: $($Dev.Nombre)" -ForegroundColor Green
            }
        }
    }

    # Actualizar archivo de estado y Dashboard HTML
    $EstadoActual | Out-File $LogStatus -Force -Encoding utf8
    Generar-Dashboard $ResultadosParaDashboard

    # --- 6. ESCUCHA DE COMANDO /STATUS ---
    try {
        $Updates = Invoke-RestMethod "https://api.telegram.org/bot$Token/getUpdates?offset=$Offset&timeout=2"
        foreach ($U in $Updates.result) {
            $Offset = $U.update_id + 1
            if ($U.message.text -eq "/status") {
                if (Test-Path $Wkhtml) {
                    & $Wkhtml --quiet --javascript-delay 500 --width 850 $HtmlFile $ImgFile
                    curl.exe -s -F "chat_id=$ChatID" -F "photo=@$ImgFile" "https://api.telegram.org/bot$Token/sendPhoto" | Out-Null
                    if (Test-Path $ImgFile) { Remove-Item $ImgFile }
                } else {
                    Send-Telegram "Dashboard HTML actualizado, pero falta wkhtmltoimage.exe para enviar la foto."
                }
            }
        }
    } catch {}

    Start-Sleep -Seconds 5
}