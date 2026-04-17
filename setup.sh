#!/usr/bin/env bash
# =============================================================================
# setup.sh — dotfiles bootstrap
# Obsługiwane systemy: macOS, Ubuntu, Fedora, Arch Linux
# =============================================================================

set -euo pipefail

# =============================================================================
# KONFIGURACJA
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/setup_$(date '+%Y-%m-%d_%H-%M-%S').log"

# Katalog źródłowy konfigów (obok skryptu)
CONFIG_SRC_DIR="${SCRIPT_DIR}/config"

# Katalog docelowy (standardowy ~/.config)
CONFIG_DST_DIR="${HOME}/.config"

# Pakiety do zainstalowania na każdym systemie
PACKAGES=(neovim tmux git curl wget ripgrep fzf lazygit)

# Symlinki: klucz = folder źródłowy w ./config/, wartość = cel w ~/.config/
declare -A SYMLINKS=(
    ["nvim"]="nvim"
    ["tmux"]="tmux"
)

# Dodatkowo plik .tmux.conf jeśli istnieje w katalogu skryptu
TMUX_CONF_SRC="${SCRIPT_DIR}/.tmux.conf"
TMUX_CONF_DST="${HOME}/.tmux.conf"

# =============================================================================
# KOLORY (tylko jeśli terminal obsługuje)
# =============================================================================

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

# =============================================================================
# LOGOWANIE
# =============================================================================

mkdir -p "${LOG_DIR}"

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_line="[${timestamp}] [${level}] ${message}"

    # Zapis do pliku (bez kolorów)
    echo "${log_line}" >> "${LOG_FILE}"

    # Wyświetl w terminalu z kolorami
    case "${level}" in
        INFO)    echo -e "${GREEN}[INFO]${NC}  ${message}" ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC}  ${message}" ;;
        ERROR)   echo -e "${RED}[ERROR]${NC} ${message}" ;;
        STEP)    echo -e "${CYAN}${BOLD}[====]${NC} ${message}" ;;
        SUCCESS) echo -e "${GREEN}${BOLD}[OK]${NC}   ${message}" ;;
    esac
}

log_info()    { log "INFO"    "$1"; }
log_warn()    { log "WARN"    "$1"; }
log_error()   { log "ERROR"   "$1"; }
log_step()    { log "STEP"    "$1"; }
log_success() { log "SUCCESS" "$1"; }

# Przechwytuj błędy niezałapane przez skrypt
trap 'log_error "Nieoczekiwany błąd w linii ${LINENO}. Sprawdź logi: ${LOG_FILE}"' ERR

# =============================================================================
# WYKRYWANIE SYSTEMU OPERACYJNEGO
# =============================================================================

detect_os() {
    log_step "Wykrywanie systemu operacyjnego..."

    OS=""
    OS_NAME=""
    PKG_MANAGER=""

    if [[ "${OSTYPE}" == "darwin"* ]]; then
        OS="macos"
        OS_NAME="macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
        PKG_MANAGER="brew"

    elif [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        local id_lower
        id_lower="$(echo "${ID}" | tr '[:upper:]' '[:lower:]')"

        case "${id_lower}" in
            ubuntu|debian|linuxmint|pop)
                OS="ubuntu"
                OS_NAME="${PRETTY_NAME:-Ubuntu}"
                PKG_MANAGER="apt"
                ;;
            fedora|rhel|centos|rocky|almalinux)
                OS="fedora"
                OS_NAME="${PRETTY_NAME:-Fedora}"
                PKG_MANAGER="dnf"
                ;;
            arch|manjaro|endeavouros|garuda)
                OS="arch"
                OS_NAME="${PRETTY_NAME:-Arch Linux}"
                PKG_MANAGER="pacman"
                ;;
            *)
                log_error "Nieobsługiwany system: ${PRETTY_NAME:-unknown} (ID=${ID})"
                exit 1
                ;;
        esac
    else
        log_error "Nie można określić systemu operacyjnego — brak /etc/os-release i nie jest to macOS."
        exit 1
    fi

    log_info "System: ${OS_NAME}"
    log_info "Identyfikator: ${OS}"
    log_info "Menadżer pakietów: ${PKG_MANAGER}"
    log_success "System operacyjny wykryty pomyślnie."
}

# =============================================================================
# INSTALACJA PAKIETÓW
# =============================================================================

check_command() {
    command -v "$1" &>/dev/null
}

install_packages() {
    log_step "Instalacja pakietów: ${PACKAGES[*]}"

    case "${OS}" in
        macos)
            install_macos
            ;;
        ubuntu)
            install_ubuntu
            ;;
        fedora)
            install_fedora
            ;;
        arch)
            install_arch
            ;;
    esac
}

# --- macOS (Homebrew) ---------------------------------------------------------

install_macos() {
    if ! check_command brew; then
        log_info "Homebrew nie znaleziony — instaluję..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            >> "${LOG_FILE}" 2>&1 \
            && log_success "Homebrew zainstalowany." \
            || { log_error "Błąd instalacji Homebrew."; exit 1; }
    else
        log_info "Homebrew już zainstalowany: $(brew --version | head -1)"
    fi

    log_info "Aktualizacja Homebrew..."
    brew update >> "${LOG_FILE}" 2>&1 || log_warn "brew update zwróciło błąd (niekriytczny)."

    # lazygit przez tap
    if ! brew tap | grep -q "jesseduffield/lazygit" 2>/dev/null; then
        log_info "Dodaję tap jesseduffield/lazygit..."
        brew tap jesseduffield/lazygit >> "${LOG_FILE}" 2>&1 || log_warn "Nie udało się dodać tap dla lazygit."
    fi

    for pkg in "${PACKAGES[@]}"; do
        if brew list --formula 2>/dev/null | grep -q "^${pkg}$"; then
            log_info "Pakiet już zainstalowany: ${pkg}"
        else
            log_info "Instaluję: ${pkg}..."
            brew install "${pkg}" >> "${LOG_FILE}" 2>&1 \
                && log_success "Zainstalowano: ${pkg}" \
                || log_error "Błąd instalacji: ${pkg} — sprawdź logi."
        fi
    done
}

# --- Ubuntu / Debian ----------------------------------------------------------

install_ubuntu() {
    log_info "Aktualizacja repozytoriów (apt update)..."
    sudo apt-get update -y >> "${LOG_FILE}" 2>&1 || log_warn "apt update zwróciło błąd."

    # lazygit nie ma w domyślnych repozytoriach Ubuntu — instalacja przez GitHub Releases
    local ubuntu_packages=()
    for pkg in "${PACKAGES[@]}"; do
        [[ "${pkg}" == "lazygit" ]] && continue
        ubuntu_packages+=("${pkg}")
    done

    log_info "Instalacja przez apt: ${ubuntu_packages[*]}"
    sudo apt-get install -y "${ubuntu_packages[@]}" >> "${LOG_FILE}" 2>&1 \
        && log_success "Pakiety apt zainstalowane." \
        || log_error "Błąd podczas instalacji apt."

    # lazygit — najnowsza wersja z GitHub
    install_lazygit_github
}

# --- Fedora / RHEL ------------------------------------------------------------

install_fedora() {
    log_info "Aktualizacja repozytoriów (dnf check-update)..."
    sudo dnf check-update -y >> "${LOG_FILE}" 2>&1 || true  # dnf zwraca 100 gdy są aktualizacje

    # lazygit przez COPR lub GitHub
    local fedora_packages=()
    for pkg in "${PACKAGES[@]}"; do
        [[ "${pkg}" == "lazygit" ]] && continue
        fedora_packages+=("${pkg}")
    done

    log_info "Instalacja przez dnf: ${fedora_packages[*]}"
    sudo dnf install -y "${fedora_packages[@]}" >> "${LOG_FILE}" 2>&1 \
        && log_success "Pakiety dnf zainstalowane." \
        || log_error "Błąd podczas instalacji dnf."

    # Próba przez COPR, fallback GitHub
    log_info "Instalacja lazygit przez COPR..."
    if sudo dnf copr enable -y atim/lazygit >> "${LOG_FILE}" 2>&1; then
        sudo dnf install -y lazygit >> "${LOG_FILE}" 2>&1 \
            && log_success "lazygit zainstalowany przez COPR." \
            || install_lazygit_github
    else
        log_warn "COPR niedostępny — próba instalacji z GitHub Releases."
        install_lazygit_github
    fi
}

# --- Arch Linux ---------------------------------------------------------------

install_arch() {
    log_info "Synchronizacja bazy pakietów (pacman -Sy)..."
    sudo pacman -Sy --noconfirm >> "${LOG_FILE}" 2>&1 || log_warn "pacman -Sy zwróciło błąd."

    log_info "Instalacja przez pacman: ${PACKAGES[*]}"
    sudo pacman -S --noconfirm --needed "${PACKAGES[@]}" >> "${LOG_FILE}" 2>&1 \
        && log_success "Pakiety pacman zainstalowane." \
        || log_error "Błąd podczas instalacji pacman."
    # Na Arch: lazygit jest w community/extra — instaluje się jak każdy pakiet
}

# --- lazygit z GitHub Releases (fallback) ------------------------------------

install_lazygit_github() {
    if check_command lazygit; then
        log_info "lazygit już zainstalowany: $(lazygit --version 2>/dev/null | head -1)"
        return 0
    fi

    log_info "Instalacja lazygit z GitHub Releases..."

    local version
    version=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')

    if [[ -z "${version}" ]]; then
        log_error "Nie udało się pobrać wersji lazygit z GitHub API."
        return 1
    fi

    local arch
    arch="$(uname -m)"
    local lg_arch="x86_64"
    [[ "${arch}" == "aarch64" || "${arch}" == "arm64" ]] && lg_arch="arm64"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local tar_file="${tmp_dir}/lazygit.tar.gz"

    curl -Lo "${tar_file}" \
        "https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_${lg_arch}.tar.gz" \
        >> "${LOG_FILE}" 2>&1

    tar -xzf "${tar_file}" -C "${tmp_dir}" >> "${LOG_FILE}" 2>&1
    sudo install "${tmp_dir}/lazygit" /usr/local/bin/lazygit >> "${LOG_FILE}" 2>&1 \
        && log_success "lazygit ${version} zainstalowany z GitHub." \
        || log_error "Błąd instalacji lazygit z GitHub."

    rm -rf "${tmp_dir}"
}

# =============================================================================
# TWORZENIE SYMLINKÓW
# =============================================================================

create_symlinks() {
    log_step "Tworzenie dowiązań symbolicznych..."

    # Upewnij się że ~/.config istnieje
    mkdir -p "${CONFIG_DST_DIR}"

    # Symlinki dla katalogów w ./config/
    for src_name in "${!SYMLINKS[@]}"; do
        local dst_name="${SYMLINKS[${src_name}]}"
        local src_path="${CONFIG_SRC_DIR}/${src_name}"
        local dst_path="${CONFIG_DST_DIR}/${dst_name}"

        if [[ ! -e "${src_path}" ]]; then
            log_warn "Źródło nie istnieje, pomijam: ${src_path}"
            continue
        fi

        if [[ -L "${dst_path}" ]]; then
            log_warn "Symlink już istnieje, pomijam: ${dst_path} → $(readlink "${dst_path}")"
            continue
        fi

        if [[ -e "${dst_path}" ]]; then
            log_warn "Cel istnieje (nie jest symlinkiem), pomijam: ${dst_path}"
            continue
        fi

        ln -s "${src_path}" "${dst_path}" \
            && log_success "Symlink: ${dst_path} → ${src_path}" \
            || log_error  "Błąd tworzenia symlinka: ${dst_path}"
    done

    # Opcjonalnie: .tmux.conf w katalogu domowym
    if [[ -f "${TMUX_CONF_SRC}" ]]; then
        if [[ -L "${TMUX_CONF_DST}" ]]; then
            log_warn "Symlink już istnieje, pomijam: ${TMUX_CONF_DST}"
        elif [[ -e "${TMUX_CONF_DST}" ]]; then
            log_warn "Plik już istnieje (nie jest symlinkiem), pomijam: ${TMUX_CONF_DST}"
        else
            ln -s "${TMUX_CONF_SRC}" "${TMUX_CONF_DST}" \
                && log_success "Symlink: ${TMUX_CONF_DST} → ${TMUX_CONF_SRC}" \
                || log_error  "Błąd tworzenia symlinka: ${TMUX_CONF_DST}"
        fi
    else
        log_info ".tmux.conf nie znaleziony w katalogu skryptu — pomijam."
    fi
}

# =============================================================================
# PODSUMOWANIE
# =============================================================================

print_summary() {
    echo ""
    echo -e "${BOLD}${CYAN}============================================${NC}"
    echo -e "${BOLD}${CYAN}  Podsumowanie setup.sh${NC}"
    echo -e "${BOLD}${CYAN}============================================${NC}"
    echo -e "  System:       ${OS_NAME}"
    echo -e "  Pkg manager:  ${PKG_MANAGER}"
    echo -e "  Log file:     ${LOG_FILE}"
    echo ""
    echo -e "  Symlinki w ${CONFIG_DST_DIR}:"
    for src_name in "${!SYMLINKS[@]}"; do
        local dst_path="${CONFIG_DST_DIR}/${SYMLINKS[${src_name}]}"
        if [[ -L "${dst_path}" ]]; then
            echo -e "    ${GREEN}✓${NC} ${dst_path}"
        else
            echo -e "    ${YELLOW}✗${NC} ${dst_path} (pominięty lub błąd)"
        fi
    done
    echo -e "${BOLD}${CYAN}============================================${NC}"
    echo ""
    log_info "Skrypt zakończony. Logi: ${LOG_FILE}"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo -e "${BOLD}${BLUE}  ██████╗  ██████╗ ████████╗███████╗██╗██╗     ███████╗███████╗${NC}"
    echo -e "${BOLD}${BLUE}  ██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝██║██║     ██╔════╝██╔════╝${NC}"
    echo -e "${BOLD}${BLUE}  ██║  ██║██║   ██║   ██║   █████╗  ██║██║     █████╗  ███████╗${NC}"
    echo -e "${BOLD}${BLUE}  ██║  ██║██║   ██║   ██║   ██╔══╝  ██║██║     ██╔══╝  ╚════██║${NC}"
    echo -e "${BOLD}${BLUE}  ██████╔╝╚██████╔╝   ██║   ██║     ██║███████╗███████╗███████║${NC}"
    echo -e "${BOLD}${BLUE}  ╚═════╝  ╚═════╝    ╚═╝   ╚═╝     ╚═╝╚══════╝╚══════╝╚══════╝${NC}"
    echo ""
    log_info "Uruchomiono setup.sh z: ${SCRIPT_DIR}"
    log_info "Logi zapisywane do: ${LOG_FILE}"
    echo ""

    detect_os
    echo ""
    install_packages
    echo ""
    create_symlinks
    echo ""
    print_summary
}

main "$@"
