# proot_debian_opencode.sh

Provisionamiento automatizado de **Termux + proot-distro (Debian)** con instalación resumible de OpenCode, Ollama y entorno de desarrollo completo.

## Objetivo

Este script transforma una instalación limpia de **Termux** en un entorno de desarrollo portátil completo dentro de un contenedor **Debian** vía proot-distro, incluyendo:

- Cliente de IA **OpenCode**
- Modelos de lenguaje local con **Ollama**
- Editor **Neovim** con lazy.nvim y plugins
- Navegación Tmux con paneles al 33%, popup flotante y atajos completos
- Explorador de archivos Ranger con temas personalizados
- Dotfiles sincronizados desde GitHub
- Audio funcional vía PulseAudio dentro del proot

## Requisitos

- **Termux** instalado desde F-Droid (no Google Play)
- Mínimo **2 GB de espacio libre** en el dispositivo
- Conexión a Internet
- Arquitectura: `aarch64` o `x86_64` (otras arquitecturas pueden funcionar parcialmente)

## Instalación

### 1. Preparar Termux

```bash
termux-setup-storage
pkg update -y && pkg upgrade -y
pkg install -y curl git
```

### 2. Ejecutar el script

```bash
curl -L https://raw.githubusercontent.com/paragon83114/proot/main/proot_debian_opencode.sh -o proot_debian_opencode.sh
chmod +x proot_debian_opencode.sh
bash proot_debian_opencode.sh
```

> El script es **resumible**: si se interrumpe (corte de luz, cierre de Termux, etc.), al volver a ejecutarlo retoma desde el último paso completado.

### 3. Finalizar

Al terminar, **reiniciá Termux** (deslizá la app y abrila de nuevo). Automaticamente iniciará sesión en Debian tras 3 segundos. Presioná cualquier tecla durante la cuenta regresiva para quedarte en la terminal de Termux.

## ¿Qué instala?

### En Termux (Fase 1)

| Componente | Descripción |
|---|---|
| `proot-distro` | Gestor de contenedores PRoot |
| `pulseaudio` | Servidor de audio con sink AAudio |
| JetBrains Mono Nerd Font | Fuente monoespaciada con iconos |
| Configuración de terminal | `termux.properties` (fullscreen, back-key = escape) |
| Auto-login a Debian | Entrada automática al proot con cancelación de 3s |

### En Debian vía proot-distro (Fase 2)

#### Paquetes base

```
neovim curl wget git lsd bat tree procps mpv stow ripgrep tmux glow locales zstd
```

#### Dotfiles (desde GitHub)

Se clona el repositorio `paragon83114/dotfiles` y se aplican con `stow`:

- **bash** — alias, prompt, variables de entorno
- **bat** — tema y configuración del paginador
- **lsd** — formato `2026/05/21` y columnas personalizadas
- **tmux** — navegación por teclado completo

#### Ranger (explorador de archivos)

Configuración completa con:

- Colores estilo tmux (azul/naranja/gris)
- Vista previa de archivos automática
- Rifle configurado para audio con PulseAudio
- Soporte de YAML/YML en el editor
- Plugin de bypass para vistas previas como root

#### OpenCode

Cliente de IA para terminal. Se integra con los dotfiles para tener el alias `oc` disponible.

#### Ollama

Servidor de modelos de lenguaje local (LLaMA, Mistral, CodeGemma, etc.). Se instala y configura un alias `start-ollama` para iniciarlo manualmente.

## Estructura de instalación

```
proot_debian_opencode.sh
├── Fase 1: Termux
│   ├── Storage
│   ├── Paquetes y actualización
│   ├── termux.properties
│   ├── JetBrains Mono Nerd Font
│   ├── proot-distro + PulseAudio
│   └── Auto-login a Debian en .bashrc
├── Fase 2: Scripts en el rootfs
│   ├── /root/proot_setup.sh      (instalador resumible)
│   └── /etc/profile.d/zz-proot-setup.sh (auto-reanudación)
└── Fase 3: Ejecución
    └── proot-distro login Debian -- bash /root/proot_setup.sh
```

## Sistema de estados (resumible)

El instalador dentro del proot usa un archivo de estado en `/root/.proot_install_state`. Los estados son:

| Estado | Paso |
|---|---|
| `init` | Paquetes base |
| `packages` | Locales |
| `locales` | Dotfiles |
| `dotfiles` | OpenCode |
| `opencode` | Ollama |
| `ollama` | — |
| `complete` | Instalación finalizada |

Si el script se interrumpe, al reingresar a Debian el perfil detecta el estado incompleto y reanuda automáticamente desde donde quedó.

## Comandos post-instalación

```bash
# Desde Termux
proot-distro login debian       # Entrar manualmente a Debian

# Desde Debian
oc                              # Iniciar OpenCode
start-ollama                    # Iniciar Ollama en segundo plano
ollama pull llama3.2            # Descargar un modelo
nvim                            # Neovim con lazy.nvim
tmux                            # Terminal multiplexor configurado
ranger                          # Explorador de archivos
```

## Atajos de teclado

### Tmux

| Tecla | Acción |
|---|---|
| `¡` (¡ inverso) | Prefix |
| `Alt + Flechas` | Navegar entre ventanas |
| `Alt + Shift + Flechas` | Crear split al 33% |
| `Alt + Espacio` | Popup flotante (80% x 80%) |
| `Alt + 1-9` | Ir/crear ventana por número |
| `Alt + x` | Cerrar panel |
| `Alt + e` | Modo copia |
| `Alt + w` | Selector de ventanas |
| `Alt + r` | Renombrar ventana |
| `Ctrl + Flechas` | Navegar entre paneles |

### Neovim

| Tecla | Acción |
|---|---|
| `Espacio + e` | Alternar explorador nvim-tree |
| `d` (en nvim-tree) | Eliminar archivo |
| `p` (en nvim-tree) | Vista previa |
| `Enter` (en nvim-tree) | Abrir archivo |

### Ranger

| Tecla | Acción |
|---|---|
| `l` o `Derecha` | Entrar a carpeta |
| `h` o `Izquierda` | Volver |
| `Espacio` | Seleccionar archivo |
| `Enter` | Abrir archivo |

## Solución de problemas

### "pulseaudio: pulseaudio no se pudo iniciar"

```bash
pulseaudio --kill 2>/dev/null || true
pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1
```

### "Ollama: connection refused"

Asegurate de haber ejecutado `start-ollama` dentro de Debian.

### El auto-login no funciona

Entrá manualmente:

```bash
proot-distro login debian
```

Y si el estado no es `complete`, ejecutá:

```bash
bash /root/proot_setup.sh
```

### Quiero evitar el auto-login

Configurá la variable antes de abrir Termux:

```bash
export BYPASS_PROOT=1
```

O simplemente presioná cualquier tecla durante la cuenta regresiva de 3 segundos.

## Notas

- El script está diseñado para **Termux nativo** (F-Droid), no para PRoot secundario
- El audio funciona vía PulseAudio en modo TCP local (`127.0.0.1`)
- Se recomienda **no abortar manualmente** durante la Fase 3 (instalación en proot)
- Los dotfiles se sincronizan desde `https://github.com/paragon83114/dotfiles.git`

## Versión

Actual: **v1.2.0**
