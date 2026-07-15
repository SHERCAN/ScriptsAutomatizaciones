#!/bin/bash
# =============================================================================
# SCADA System - Configuración de Firewall (UFW) y SSH en Ubuntu VPS
# =============================================================================
#
# INSTRUCCIONES DE DESPLIEGUE EN EL VPS:
# 1. Sube este archivo (configure_firewall.sh) al VPS.
# 2. Si vienes de Windows, limpia los saltos de línea (CRLF) en el mismo archivo:
#       sed -i 's/\r$//' configure_firewall.sh
# 3. Asigna permisos de ejecución al archivo:
#       chmod +x configure_firewall.sh
# 4. Ejecútalo como superusuario (root):
#       sudo ./configure_firewall.sh
#
# PASOS PARA VERIFICAR EL CAMBIO DE PUERTO SSH (Si se seleccionó cambiar puerto):
# 1. Al terminar este script, NO CIERRES la terminal activa actual. Mantenla abierta como respaldo.
# 2. Abre una NUEVA terminal en tu máquina local.
# 3. Intenta conectar al VPS usando el nuevo puerto:
#       ssh -p <NUEVO_PUERTO> usuario@tu_ip_del_servidor
# 4. Si logras iniciar sesión correctamente en la nueva ventana:
#       - ¡El cambio fue exitoso!
#       - En la terminal original, cierra definitivamente el puerto 22 ejecutando:
#         sudo ufw delete allow 22/tcp
#         sudo ufw reload
# 5. Si algo falla y no puedes conectar por el nuevo puerto, aún tienes la terminal 
#    original abierta para revisar los logs de SSH (journalctl -u ssh) y corregir.
# =============================================================================

# Asegurar que se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Por favor, ejecuta este script como root (sudo)."
    exit 1
fi

# Validar sistema operativo (Ubuntu/Debian)
if [ ! -f /etc/debian_version ]; then
    echo "❌ Este script está diseñado específicamente para sistemas basados en Ubuntu/Debian."
    exit 1
fi

echo "🔄 Iniciando configuración..."

# 1. Instalar UFW si no está instalado
if ! command -v ufw >/dev/null 2>&1; then
    echo "📦 Instalando UFW..."
    apt-get update && apt-get install -y ufw
fi

# 2. Configurar políticas por defecto de UFW
echo "🛡️ Configurando políticas por defecto del Firewall..."
ufw default deny incoming
ufw default allow outgoing

# 3. Abrir puertos necesarios para el proyecto SCADA
echo "📥 Abriendo puertos de entrada necesarios..."
ufw allow 80/tcp      # HTTP para Traefik / Dokploy
ufw allow 443/tcp     # HTTPS para Traefik / Dokploy
ufw allow 1883/tcp    # MQTT (Agentes sin TLS)
ufw allow 8883/tcp    # MQTT (Agentes con TLS)
ufw allow 9883/tcp    # MQTT (Agentes sobre WebSockets)
ufw allow 3000/tcp    # Dokploy Panel

# 4. Preguntar interactivamente por el puerto SSH
SSH_PORT=22
echo ""
read -p "❓ ¿Deseas cambiar el puerto SSH por defecto (22)? [s/N]: " change_ssh
change_ssh=$(echo "$change_ssh" | tr '[:upper:]' '[:lower:]')

if [[ "$change_ssh" == "s" || "$change_ssh" == "si" || "$change_ssh" == "y" || "$change_ssh" == "yes" ]]; then
    read -p "👉 Introduce el nuevo puerto SSH deseado (1024-65535): " custom_port
    # Validar que sea un número válido en rango no privilegiado
    if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1024 ] && [ "$custom_port" -le 65535 ]; then
        SSH_PORT=$custom_port
        echo "✅ Se configurará el puerto SSH: $SSH_PORT"
    else
        echo "⚠️ Puerto no válido o fuera de rango. Se mantendrá el puerto 22 por defecto."
    fi
fi

# 5. Configurar puertos SSH en UFW
echo "🔑 Configurando puertos SSH en el firewall..."
ufw allow 22/tcp  # Siempre abrimos temporalmente el 22 para evitar quedarnos bloqueados
if [ "$SSH_PORT" -ne 22 ]; then
    ufw allow "$SSH_PORT/tcp"
fi

# 6. Modificar el puerto SSH en la configuración del servidor si es diferente a 22
if [ "$SSH_PORT" -ne 22 ]; then
    echo "📝 Modificando puerto SSH en /etc/ssh/sshd_config..."
    if [ -f /etc/ssh/sshd_config ]; then
        # Hacer respaldo de la configuración actual
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
        
        # Comentar cualquier línea de Port existente y añadir el nuevo
        sed -i 's/^Port /#Port /g' /etc/ssh/sshd_config
        
        # Asegurar que el nuevo puerto esté configurado
        if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
            echo -e "\nPort $SSH_PORT" >> /etc/ssh/sshd_config
        fi
    fi

    # 7. Manejar la activación de sockets de systemd para SSH (Ubuntu 22.10 o superior)
    if systemctl is-active --quiet ssh.socket; then
        echo "⚙️ Detectada activación por socket de Systemd para SSH. Ajustando puerto..."
        mkdir -p /etc/systemd/system/ssh.socket.d/
        cat <<EOF > /etc/systemd/system/ssh.socket.d/addresses.conf
[Socket]
ListenStream=
ListenStream=0.0.0.0:$SSH_PORT
ListenStream=[::]:$SSH_PORT
EOF
        echo "🔄 Recargando daemon de Systemd y reiniciando socket..."
        systemctl daemon-reload
        systemctl restart ssh.socket
    fi

    # 8. Reiniciar el servicio SSH tradicional
    echo "🔄 Reiniciando servicio SSH..."
    if systemctl is-active --quiet ssh; then
        systemctl restart ssh
    elif systemctl is-active --quiet sshd; then
        systemctl restart sshd
    else
        service ssh restart || service sshd restart
    fi
fi

# 9. Activar UFW
echo "🔥 Habilitando UFW..."
echo "y" | ufw enable

echo ""
echo "====================================================================="
echo "🎉 ¡Configuración de Firewall (UFW) completada con éxito!"
echo "====================================================================="
echo "Reglas de UFW activas:"
echo "  - Puertos de Aplicación abiertos: 80, 443, 1883, 8883, 9883, 3000 (TCP)"
echo "  - Puerto SSH actual configurado: $SSH_PORT/tcp"
if [ "$SSH_PORT" -ne 22 ]; then
    echo "  - Puerto SSH Temporal abierto: 22/tcp"
fi
echo "====================================================================="

if [ "$SSH_PORT" -ne 22 ]; then
    echo "⚠️  SIGUE ESTOS PASOS AHORA MISMO PARA VERIFICAR EL NUEVO PUERTO:"
    echo "1. NO CIERRES ESTA TERMINAL ACTUAL."
    echo "2. Abre una NUEVA terminal en tu PC local."
    echo "3. Ejecuta el comando de conexión con el nuevo puerto:"
    echo "     ssh -p $SSH_PORT tu_usuario@ip_de_tu_servidor"
    echo "4. Si conectas correctamente, ejecuta esto en esta ventana actual para"
    echo "   cerrar el puerto 22 definitivamente por seguridad:"
    echo "     sudo ufw delete allow 22/tcp"
    echo "     sudo ufw reload"
    echo "====================================================================="
fi
