#!/bin/bash

# ==========================================
# proot_debian_opencode.sh
# Provisioning de Termux + proot-distro (Debian)
# con instalación resumible y auto-reanudación
# ==========================================

VERSION="1.2.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DEBIAN_DISTRO="debian"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/JetBrainsMono/Ligatures/Regular/JetBrainsMonoNerdFont-Regular.ttf"
DOTFILES_REPO="https://github.com/paragon83114/dotfiles.git"

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

set -e

# Asegurar modo no interactivo para evitar bloqueos
export DEBIAN_FRONTEND=noninteractive

# ==========================================
# VALIDACIÓN INICIAL Y COMPROBACIONES
# ==========================================
if [ -z "$TERMUX_VERSION" ]; then
    error "Este script debe ejecutarse dentro de Termux."
fi

log "proot_debian_opencode.sh v${VERSION}"

# 1. Comprobar conexión a Internet
check_internet() {
    log "Comprobando conexión a Internet..."
    if ! curl -s --connect-timeout 5 https://1.1.1.1 >/dev/null; then
        error "No hay conexión a Internet. Por favor, conéctate a una red activa."
    fi
}
check_internet

# 2. Comprobar arquitectura de CPU
check_architecture() {
    local arch=$(uname -m)
    log "Detectando arquitectura de CPU: $arch"
    if [ "$arch" != "aarch64" ] && [ "$arch" != "x86_64" ]; then
        warn "Arquitectura no estándar ($arch). Algunas herramientas (como Ollama) podrían no ser compatibles."
        read -p "¿Deseas continuar? (s/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            error "Instalación abortada por incompatibilidad de arquitectura."
        fi
    fi
}
check_architecture

# 3. Comprobar espacio libre en disco (~2GB mínimo)
check_disk_space() {
    log "Comprobando espacio libre en disco..."
    local free_kb=$(df -k "$HOME" | awk 'NR==2 {print $4}')
    local req_kb=2000000 # 2 GB
    if [ "$free_kb" -lt "$req_kb" ]; then
        warn "Espacio en disco insuficiente: $(df -h "$HOME" | awk 'NR==2 {print $4}') libres. Se recomiendan al menos 2GB."
        read -p "¿Deseas continuar de todas formas? (s/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            error "Instalación cancelada para prevenir fallos por falta de espacio."
        fi
    else
        log "Espacio libre verificado: $(df -h "$HOME" | awk 'NR==2 {print $4}') libres."
    fi
}
check_disk_space


# ==========================================
# FASE 1: Setup completo de Termux
# (todo lo de Termux queda listo antes de tocar el proot)
# ==========================================
log "=== FASE 1: Configuración de Termux ==="

# --- Storage ---
if [ ! -e ~/storage ]; then
    log "Configurando acceso al almacenamiento..."
    termux-setup-storage
else
    log "Almacenamiento ya configurado."
fi

touch ~/.hushlogin

# --- Paquetes y actualización ---
log "Actualizando paquetes de Termux..."
termux-change-repo
pkg update -y && pkg upgrade -y -o Dpkg::Options::="--force-confnew"

# --- termux.properties ---
log "Configurando termux.properties..."
PROP_FILE="$HOME/.termux/termux.properties"
mkdir -p "$(dirname "$PROP_FILE")"
if [ ! -s "$PROP_FILE" ]; then
    cat > "$PROP_FILE" << 'PROPEOF'
fullscreen = true
extra-keys = []
back-key=escape
PROPEOF
else
    sed -i 's/^# *fullscreen = true/fullscreen = true/' "$PROP_FILE"
    sed -i 's/^# *extra-keys = .*/extra-keys = []/' "$PROP_FILE"
    sed -i 's/^# *back-key=escape/back-key=escape/' "$PROP_FILE"
fi

# --- Fuente ---
if [ ! -e ~/.termux/font.ttf ]; then
    log "Descargando JetBrains Mono Nerd Font..."
    curl -L "$FONT_URL" -o ~/.termux/font.ttf
    termux-reload-settings
fi

# --- proot-distro y pulseaudio ---
log "Instalando proot-distro y PulseAudio en Termux..."
pkg install -y proot-distro pulseaudio

# Configurar PulseAudio en Termux para usar AAudio (compatible y moderno)
PULSE_CONF="$PREFIX/etc/pulse/default.pa"
if [ -f "$PULSE_CONF" ]; then
    log "Configurando PulseAudio en Termux para usar el sink de AAudio..."
    sed -i 's/^\s*load-module module-sles-sink/# load-module module-sles-sink/' "$PULSE_CONF"
    sed -i 's/^#\s*load-module module-aaudio-sink/load-module module-aaudio-sink/' "$PULSE_CONF"
fi

# Detectar la ruta real del rootfs (compatible con v4.x legacy y v5.0+)
detect_proot_root() {
    local new="$PREFIX/var/lib/proot-distro/containers/$DEBIAN_DISTRO/rootfs"
    local legacy="$PREFIX/var/lib/proot-distro/installed-rootfs/$DEBIAN_DISTRO"
    if [ -d "$new" ]; then
        echo "$new"
    elif [ -d "$legacy" ]; then
        echo "$legacy"
    else
        echo ""
    fi
}

PROOT_ROOT=$(detect_proot_root)

if [ -z "$PROOT_ROOT" ]; then
    log "Instalando Debian (latest) en proot..."
    proot-distro install "$DEBIAN_DISTRO"
    PROOT_ROOT=$(detect_proot_root)
else
    warn "Debian ya está instalado, saltando instalación."
fi

if [ -z "$PROOT_ROOT" ] || [ ! -d "$PROOT_ROOT" ]; then
    error "No se pudo determinar la ruta del rootfs de $DEBIAN_DISTRO"
fi

# --- Auto-login al proot con interruptor de escape de 3s (Evita bloqueos de Termux) ---
log "Configurando auto-login al proot con opción de cancelación..."
if ! grep -q "proot-distro login $DEBIAN_DISTRO" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << BASHRC_EOF

# Auto-login a proot-distro (Debian) con opción de cancelación (3s)
if [ -z "\$BYPASS_PROOT" ] && [ "\$TERMUX_VERSION" ]; then
    # Matar instancias colgadas de PulseAudio e iniciar el servidor TCP de forma limpia
    pulseaudio --kill >/dev/null 2>&1 || true
    pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1 >/dev/null 2>&1 || true

    echo -e "\n\033[1;36m[Termux]\033[0m Iniciando Debian en 3 segundos..."
    echo -e "\033[1;33m[Presiona cualquier tecla para quedarte en la consola de Termux]\033[0m"
    if read -t 3 -n 1; then
        echo -e "\n\033[1;32m[Termux]\033[0m Entorno local Termux. Usa 'proot-distro login $DEBIAN_DISTRO' para entrar manualmente."
    else
        echo -e "\n\033[1;32m[Termux]\033[0m Iniciando Debian..."
        proot-distro login $DEBIAN_DISTRO
    fi
fi
BASHRC_EOF
fi

log "Termux completamente configurado."

# ==========================================
# FASE 2: Inyectar scripts dentro del rootfs de Debian
# ==========================================
log "=== FASE 2: Preparando scripts en el proot ==="

mkdir -p "$PROOT_ROOT/root"
mkdir -p "$PROOT_ROOT/etc/profile.d"

# --- Script de instalación resumible (/root/proot_setup.sh) ---
log "Escribiendo /root/proot_setup.sh..."
cat > "$PROOT_ROOT/root/proot_setup.sh" << SETUP_EOF
#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
STATE_FILE="/root/.proot_install_state"

log()  { echo -e "\${GREEN}[PROOT]\${NC} \$1"; }
warn() { echo -e "\${YELLOW}[PROOT]\${NC} \$1"; }

STATE=\$(cat "\$STATE_FILE" 2>/dev/null || echo "init")
log "Estado de instalación: \$STATE"

export DEBIAN_FRONTEND=noninteractive

# ==========================================
# Paso 1: Paquetes base
# ==========================================
if [ "\$STATE" = "init" ]; then
    log "Actualizando e instalando paquetes base..."
    apt update && apt upgrade -y -o Dpkg::Options::="--force-confnew"
    apt install -y neovim curl wget git lsd bat tree procps mpv stow ripgrep tmux glow locales zstd
    echo "packages" > "\$STATE_FILE"
    STATE="packages"
    log "Paquetes base instalados."
fi

# ==========================================
# Paso 2: Locales
# ==========================================
if [ "\$STATE" = "packages" ]; then
    log "Configurando locales..."
    sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
    locale-gen
    echo "locales" > "\$STATE_FILE"
    STATE="locales"
    log "Locales configurados."
fi

# ==========================================
# Paso 3: Dotfiles
# ==========================================
if [ "\$STATE" = "locales" ]; then
    log "Configurando dotfiles..."
    cd ~

    if [ -d dotfiles ]; then
        warn "Eliminando dotfiles existentes..."
        rm -rf dotfiles
    fi
    git clone ${DOTFILES_REPO}

    # Eliminar cualquier referencia a fzf de los dotfiles clonados para cumplir con su eliminación completa
    log "Removiendo referencias a fzf de los dotfiles..."
    find ~/dotfiles -type f -exec sed -i -e '/fzf/d' -e '/FZF/d' {} + 2>/dev/null || true

    safe_backup() {
        if [ -e "\$1" ]; then
            echo "  Backup de \$1 -> \$1.bak_\$(date +%Y%m%d_%H%M%S)"
            mv "\$1" "\$1.bak_\$(date +%Y%m%d_%H%M%S)"
        fi
    }

    safe_backup ~/.bashrc
    safe_backup ~/.config/bat
    safe_backup ~/.config/lsd
    safe_backup ~/.config/tmux

    # Configurar variables de entorno globales de sonido y paginador en dotfiles antes de stowear
    echo "export PULSE_SERVER=127.0.0.1" >> ~/dotfiles/bash/.bashrc
    echo "export LESS=\"-R\"" >> ~/dotfiles/bash/.bashrc

    mkdir -p ~/.config
    cd ~/dotfiles
    # Usar --adopt para fusionar de forma segura y evitar fallos si existen archivos en conflicto
    stow --adopt bash bat lsd tmux
    git reset --hard HEAD
    
    cp ~/dotfiles/keys/keys.md ~/ 2>/dev/null || true

    # --- Configuración automática de Ranger ---
    log "Ajustando configuración de Ranger..."
    mkdir -p ~/.config/ranger/plugins

    # Copiar archivo de asociaciones de rifle por defecto si no existe
    if [ ! -f ~/.config/ranger/rifle.conf ]; then
        cp /usr/share/doc/ranger/config/rifle.conf ~/.config/ranger/rifle.conf 2>/dev/null || \
        cp /usr/lib/python3/dist-packages/ranger/config/rifle.conf ~/.config/ranger/rifle.conf 2>/dev/null || true
    fi

    # Modificar la regla de audio de mpv para quitar terminal y forzar PulseAudio
    if [ -f ~/.config/ranger/rifle.conf ]; then
        sed -i 's/mime ^audio|ogg\$, terminal, has mpv      = mpv -- "\$@"/mime ^audio|ogg\$, has mpv      = mpv --ao=pulse -- "\$@"/' ~/.config/ranger/rifle.conf
        # Asegurar que yaml/yml se abran directamente con el editor principal sin preguntar
        sed -i 's/!mime ^text, label editor, ext xml|json|csv|tex|py|pl|rb|js|sh|php = \\\${VISUAL:-\\\$EDITOR} -- "\\\$@"/!mime ^text, label editor, ext xml|json|csv|tex|py|pl|rb|js|sh|php|yml|yaml = \\\${VISUAL:-\\\$EDITOR} -- "\\\$@"/' ~/.config/ranger/rifle.conf
        sed -i 's/!mime ^text, label pager,  ext xml|json|csv|tex|py|pl|rb|js|sh|php = "\\\$PAGER" -- "\\\$@"/!mime ^text, label pager,  ext xml|json|csv|tex|py|pl|rb|js|sh|php|yml|yaml = "\\\$PAGER" -- "\\\$@"/' ~/.config/ranger/rifle.conf
        sed -i 's/              !mime ^text, !ext xml|json|csv|tex|py|pl|rb|js|sh|php  = ask/              !mime ^text, !ext xml|json|csv|tex|py|pl|rb|js|sh|php|yml|yaml  = ask/' ~/.config/ranger/rifle.conf
        sed -i 's/label editor, !mime ^text, !ext xml|json|csv|tex|py|pl|rb|js|sh|php  = \\\${VISUAL:-\\\$EDITOR} -- "\\\$@"/label editor, !mime ^text, !ext xml|json|csv|tex|py|pl|rb|js|sh|php|yml|yaml  = \\\${VISUAL:-\\\$EDITOR} -- "\\\$@"/' ~/.config/ranger/rifle.conf
        sed -i 's/label pager,  !mime ^text, !ext xml|json|csv|tex|py|pl|rb|js|sh|php  = "\\\$PAGER" -- "\\\$@"/label pager,  !mime ^text, !ext xml|json|csv|tex|py|pl|rb|js|sh|php|yml|yaml  = "\\\$PAGER" -- "\\\$@"/' ~/.config/ranger/rifle.conf
    fi

    # Crear archivo rc.conf para Ranger con opciones estéticas
    cat > ~/.config/ranger/rc.conf << 'RCCONF_EOF'
set colorscheme tmux_match
set draw_borders separators
set hostname_in_titlebar false
set tilde_in_titlebar true
set show_hidden true
set preview_files true
set use_preview_script true
set column_ratios 1,1,1

# Teclas personalizadas
map l enter_dir
map <RIGHT> enter_dir
map <CR> move right=1
RCCONF_EOF

    # Crear el plugin de bypass para root (vistas previas automáticas)
    cat > ~/.config/ranger/plugins/force_preview.py << 'PLUG_EOF'
import ranger.api

old_hook_init = ranger.api.hook_init

def hook_init(fm):
    fm.settings.preview_files = True
    fm.settings.use_preview_script = True
    return old_hook_init(fm)

ranger.api.hook_init = hook_init
PLUG_EOF

    # Crear tema de color personalizado estilo tmux
    mkdir -p ~/.config/ranger/colorschemes
    cat > ~/.config/ranger/colorschemes/tmux_match.py << 'THEME_EOF'
from ranger.colorschemes.solarized import Solarized
from ranger.gui.color import reverse, bold, default

class Scheme(Solarized):
    def use(self, context):
        fg, bg, attr = Solarized.use(self, context)

        if context.in_browser:
            # Files are colour244 (grey) by default when not selected
            if not context.directory and not context.selected:
                fg = 244

            # Directories are colour214 (orange)
            if context.directory:
                fg = 214
                attr |= bold

            # Selection bar is colour24 (blue background) with white text
            if context.selected:
                attr &= ~reverse
                bg = 24
                fg = 231
                attr |= bold

        return fg, bg, attr
THEME_EOF

    # Crear el comando personalizado para no abrir al presionar derecha
    cat > ~/.config/ranger/commands.py << 'CMD_EOF'
from ranger.api.commands import Command

class enter_dir(Command):
    def execute(self):
        if self.fm.thisfile.is_directory:
            self.fm.enter_dir(self.fm.thisfile.path)
CMD_EOF

    echo "dotfiles" > "\$STATE_FILE"
    STATE="dotfiles"
    log "Dotfiles y configuraciones de Ranger completadas."
fi

# ==========================================
# Paso 4: OpenCode
# ==========================================
if [ "\$STATE" = "dotfiles" ]; then
    log "Instalando OpenCode..."
    curl -fsSL https://opencode.ai/install | bash
    echo "opencode" > "\$STATE_FILE"
    STATE="opencode"
    log "OpenCode instalado."
fi

# ==========================================
# Paso 5: Ollama
# ==========================================
if [ "\$STATE" = "opencode" ]; then
    log "Instalando Ollama (latest)..."
    curl -fsSL https://ollama.com/install.sh | sh
    
    # Añadir alias útil para iniciar Ollama manualmente en segundo plano
    if ! grep -q "alias start-ollama" ~/.bashrc 2>/dev/null; then
        echo "alias start-ollama='ollama serve >/dev/null 2>&1 &'" >> ~/.bashrc
    fi

    echo "ollama" > "\$STATE_FILE"
    STATE="ollama"
    log "Ollama instalado."
fi

# ==========================================
# Completado
# ==========================================
echo "complete" > "\$STATE_FILE"
echo -e "\${GREEN}[PROOT] Instalación del proot completada.\${NC}"
SETUP_EOF

chmod +x "$PROOT_ROOT/root/proot_setup.sh"

# --- Script de auto-reanudación en profile.d ---
log "Escribiendo /etc/profile.d/zz-proot-setup.sh..."
cat > "$PROOT_ROOT/etc/profile.d/zz-proot-setup.sh" << 'PROFILE_EOF'
#!/bin/bash
STATE=$(cat /root/.proot_install_state 2>/dev/null || echo "init")
if [ "$STATE" != "complete" ]; then
    echo -e "\033[1;33m[PROOT] Instalación incompleta (estado: $STATE). Reanudando...\033[0m"
    bash /root/proot_setup.sh
fi
PROFILE_EOF

chmod +x "$PROOT_ROOT/etc/profile.d/zz-proot-setup.sh"

# ==========================================
# FASE 3: Ejecutar el instalador en el proot
# ==========================================
log "=== FASE 3: Ejecutando instalación en el proot ==="
proot-distro login "$DEBIAN_DISTRO" -- bash /root/proot_setup.sh

log "=== Todo listo. Reinicia Termux para entrar al proot. ==="
log "Guía rápida para Ollama: Puedes iniciarlo dentro de Debian usando el alias 'start-ollama'."
