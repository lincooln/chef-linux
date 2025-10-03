#!/bin/bash
###############################################################################
# ПОВАР — Утилита управления рецептами настройки Linux-систем
# Гибридная версия: дружелюбная к пользователям И разработчикам
#
# Расширение книг: .inf
# Автор: Lincooln
# Версия: 4.2 - Умный контроль зависимостей + исправленный спиннер
# Репозиторий: https://github.com/lincooln/chef-linux
###############################################################################
# =============================================================================
# НАСТРОЙКИ И ПЕРЕМЕННЫЕ
# =============================================================================
DEBUG=1
VERBOSE=1
PROGRAM_NAME="Повар"
SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="4.2"
# Пути поиска книг (.inf)
RECIPE_PATHS=(
    "$SELF_PATH/рецепты"
    "$SELF_PATH/книги_рецептов"
    "$SELF_PATH"
)
EDITOR=""
# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
# =============================================================================
# КОНФИГУРАЦИЯ ПАКЕТНЫХ МЕНЕДЖЕРОВ - ПРОСТАЯ ДЛЯ РАСШИРЕНИЯ
# =============================================================================
declare -A DISTRO_MAPPING=(
    ["debian"]="apt"
    ["ubuntu"]="apt"
    ["linuxmint"]="apt"
    ["proxmox"]="apt"
    ["astra"]="apt"
    ["kali"]="apt"
    ["alt"]="alt"
    ["altlinux"]="alt"
    ["simply"]="apt"
    ["redos"]="dnf"
    ["fedora"]="dnf"
    ["rhel"]="dnf"
    ["centos"]="dnf"
    ["arch"]="pacman"
    ["manjaro"]="pacman"
    ["endeavouros"]="pacman"
    ["opensuse"]="zypper"
    ["suse"]="zypper"
)
declare -A PROVIDER_CONFIGS=(
    ["apt:pkgmgr"]="apt-get"
    ["apt:install"]="install -y"
    ["apt:remove"]="remove -y --purge"
    ["apt:name"]="APT-based (Debian/Ubuntu)"
    ["alt:pkgmgr"]="apt-get"
    ["alt:install"]="install -y"
    ["alt:remove"]="remove -y --purge"
    ["alt:name"]="ALT Linux"
    ["dnf:pkgmgr"]="dnf"
    ["dnf:install"]="install -y"
    ["dnf:remove"]="remove -y"
    ["dnf:name"]="DNF-based (Fedora/RedHat)"
    ["pacman:pkgmgr"]="pacman"
    ["pacman:install"]="-S --noconfirm"
    ["pacman:remove"]="-Rns --noconfirm"
    ["pacman:name"]="Pacman-based (Arch)"
    ["zypper:pkgmgr"]="zypper"
    ["zypper:install"]="install -y"
    ["zypper:remove"]="remove -y"
    ["zypper:name"]="Zypper-based (openSUSE)"
)
# =============================================================================
# ГЛОБАЛЬНЫЕ СТРУКТУРЫ ДАННЫХ
# =============================================================================
declare -A DISTRO_PROVIDERS
declare -A RECIPE_NAME RECIPE_INGREDIENTS RECIPE_CLEANUPS RECIPE_SPICES
declare -gA FOUND_RECIPES PARSED_RECIPE
CLIENT=""
RECIPE_FILE=""
SELECTED=""
CURRENT_PROVIDER_TYPE=""
# =============================================================================
# РАСШИРЕННАЯ СИСТЕМА ЛОГГИРОВАНИЯ
# =============================================================================
log_debug()    { [[ $DEBUG -eq 1 ]] && echo -e "${MAGENTA}[ОТЛАДКА]${NC} $1" >&2; }
log_info()     { echo -e "${BLUE}[ИНФО]${NC} $1"; }
log_detail()   { [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}[ДЕТАЛИ]${NC} $1"; }
log_warn()     { echo -e "${YELLOW}[ВНИМАНИЕ]${NC} $1"; }
log_error()    { echo -e "${RED}[ОШИБКА]${NC} $1" >&2; }
log_success()  { echo -e "${GREEN}[УСПЕХ]${NC} $1"; }
log_step()     { echo -e "${GREEN}➜${NC} $1"; }
friendly_message() {
    local type="$1" message="$2" hint="$3"
    case "$type" in
        "welcome") echo -e "${GREEN} ДОБРО ПОЖАЛОВАТЬ  ПОВАР v$VERSION ${NC}";;
        "help")    echo -e "${CYAN}💡 Подсказка:${NC} $message"; [[ -n "$hint" ]] && echo -e "${CYAN}   🠖 ${hint}${NC}";;
        "tip")     echo -e "${YELLOW}💡 Совет:${NC} $message";;
        "developer") echo -e "${MAGENTA}👨‍💻 Для разработчика:${NC} $message"; [[ -n "$hint" ]] && echo -e "${MAGENTA}   🠖 ${hint}${NC}";;
    esac
}
# =============================================================================
# УПРОЩЕННАЯ СИСТЕМА ПРОВАЙДЕРОВ
# =============================================================================
init_providers() {
    log_debug "Инициализация системы провайдеров..."
### ALT Linux provider functions
    provider_alt_check_install() {
        apt-cache show "$1" &>/dev/null || { log_warn "Пакет '$1' не найден в репозиториях"; return 1; }
        return 0
    }
    provider_alt_check_remove()  {
        rpm -q "$1" &>/dev/null || { log_warn "Пакет '$1' не установлен"; return 1; }
        return 0
    }
    provider_alt_deps_install()  {
        apt-cache depends --with-recommends "$1" 2>/dev/null | grep -E "^[[:space:]]*Depends" | cut -d: -f2- | sed 's/^[[:space:]]*//' | sort -u
    }
    provider_alt_deps_remove()   {
        apt-cache rdepends "$1" 2>/dev/null | tail -n +3 | grep -v "^[[:space:]]" | sort -u
    }
### APT provider functions
    provider_apt_check_install() {
        apt-cache show "$1" &>/dev/null || { log_warn "Пакет '$1' не найден в репозиториях"; return 1; }
        return 0
    }
    provider_apt_check_remove()  {
        dpkg -l "$1" &>/dev/null || { log_warn "Пакет '$1' не установлен"; return 1; }
        return 0
    }
    provider_apt_deps_install()  {
        apt-cache depends "$1" 2>/dev/null | grep -E "^[[:space:]]*Depends" | cut -d: -f2- | sed 's/^[[:space:]]*//' | sort -u
    }
    provider_apt_deps_remove()   {
        apt-cache rdepends "$1" 2>/dev/null | tail -n +3 | grep -v "^ " | sort -u
    }
### DNF provider functions
    provider_dnf_check_install() {
        dnf list available "$1" &>/dev/null || { log_warn "Пакет '$1' не доступен в репозиториях"; return 1; }
        return 0
    }
    provider_dnf_check_remove()  {
        rpm -q "$1" &>/dev/null || { log_warn "Пакет '$1' не установлен"; return 1; }
        return 0
    }
    provider_dnf_deps_install()  {
        dnf deplist "$1" 2>/dev/null | grep "dependency" | awk '{print $2}' | sort -u
    }
    provider_dnf_deps_remove()   {
        dnf repoquery --whatrequires "$1" 2>/dev/null | head -n 20
    }
### Pacman provider functions
    provider_pacman_check_install() {
        pacman -Si "$1" &>/dev/null || { log_warn "Пакет '$1' не найден в репозиториях"; return 1; }
        return 0
    }
    provider_pacman_check_remove()  {
        pacman -Q "$1" &>/dev/null || { log_warn "Пакет '$1' не установлен"; return 1; }
        return 0
    }
    provider_pacman_deps_install()  {
        pacman -Si "$1" 2>/dev/null | grep "Depends On" | cut -d: -f2 | sed 's/^ //'
    }
    provider_pacman_deps_remove()   {
        pacman -Qi "$1" 2>/dev/null | grep -A5 "Required By" | tail -n +2
    }
### Zypper provider functions
    provider_zypper_check_install() {
        zypper search "$1" &>/dev/null || { log_warn "Пакет '$1' не найден"; return 1; }
        return 0
    }
    provider_zypper_check_remove()  {
        rpm -q "$1" &>/dev/null || { log_warn "Пакет '$1' не установлен"; return 1; }
        return 0
    }
    provider_zypper_deps_install()  {
        zypper info "$1" 2>/dev/null | grep "Requires" | cut -d: -f2-
    }
    provider_zypper_deps_remove()   {
        zypper what-requires "$1" 2>/dev/null | grep -v "Reading" | head -n 10
    }
}
register_providers() {
    log_debug "Регистрация провайдеров для дистрибутивов..."
    for distro in "${!DISTRO_MAPPING[@]}"; do
        local provider_type="${DISTRO_MAPPING[$distro]}"
        if [[ -z "${PROVIDER_CONFIGS[$provider_type:pkgmgr]}" ]]; then
            log_warn "Тип провайдера '$provider_type' не сконфигурирован для дистрибутива '$distro'"
            continue
        fi
        for key in "${!PROVIDER_CONFIGS[@]}"; do
            if [[ "$key" == "$provider_type:"* ]]; then
                local field="${key#$provider_type:}"
                DISTRO_PROVIDERS["$distro:$field"]="${PROVIDER_CONFIGS[$key]}"
            fi
        done
        DISTRO_PROVIDERS["$distro:check_install"]="provider_${provider_type}_check_install"
        DISTRO_PROVIDERS["$distro:check_remove"]="provider_${provider_type}_check_remove"
        DISTRO_PROVIDERS["$distro:deps_install"]="provider_${provider_type}_deps_install"
        DISTRO_PROVIDERS["$distro:deps_remove"]="provider_${provider_type}_deps_remove"
        log_debug "Зарегистрирован: $distro → $provider_type"
    done
}
detect_provider() {
    log_step "Определение пакетного менеджера..."
    if [[ -n "${DISTRO_MAPPING[$CLIENT]}" ]]; then
        CURRENT_PROVIDER_TYPE="${DISTRO_MAPPING[$CLIENT]}"
        local provider_name="${PROVIDER_CONFIGS[$CURRENT_PROVIDER_TYPE:name]}"
        log_success "Используется: $provider_name"
        return 0
    else
        log_error "Дистрибутив '$CLIENT' не поддерживается"
        show_distro_help
        return 1
    fi
}
show_distro_help() {
    echo; friendly_message "developer" "Добавление поддержки нового дистрибутива" "Это займет 2 минуты!"; echo
    echo -e "${CYAN}ШАГ 1:${NC} Добавьте дистрибутив в маппинг"
    echo "  В файле: ${BASH_SOURCE[0]}"
    echo "  Найдите: declare -A DISTRO_MAPPING"
    echo "  Добавьте: [\"ваш-дистрибутив\"]=\"тип-пакетного-менеджера\""
    echo
    echo -e "${CYAN}ШАГ 2:${NC} Проверьте доступные типы:"
    echo -e "  ${YELLOW}apt${NC}    - Debian, Ubuntu"
    echo -e "  ${YELLOW}alt${NC}    - ALT Linux"
    echo -e "  ${YELLOW}dnf${NC}    - Fedora, RedOS"
    echo -e "  ${YELLOW}pacman${NC} - Arch, Manjaro"
    echo -e "  ${YELLOW}zypper${NC} - openSUSE"
    echo -e "${CYAN}ПРИМЕР:${NC} [\"simply\"]=\"apt\""
    echo
    echo -e "${CYAN}СУЩЕСТВУЮЩИЕ:${NC}"
    for distro in "${!DISTRO_MAPPING[@]}"; do echo "  • $distro → ${DISTRO_MAPPING[$distro]}"; done
    echo
}
get_provider_field() {
    local distro="$1" field="$2"
    local value="${DISTRO_PROVIDERS[$distro:$field]}"
    if [[ -z "$value" ]]; then
        log_debug "Поле '$field' не найдено для '$distro'"
        if [[ $DEBUG -eq 1 ]]; then
            friendly_message "developer" "Отсутствует поле '$field' для '$distro'" "Добавьте в PROVIDER_CONFIGS: [\"$CURRENT_PROVIDER_TYPE:$field\"]=\"значение\""
        fi
    fi
    echo "$value"
}
call_provider_func() {
    local distro="$1" func_type="$2" pkg="$3"
    local func_name="$(get_provider_field "$distro" "$func_type")"
    if [[ -n "$func_name" ]] && declare -f "$func_name" >/dev/null; then
        "$func_name" "$pkg"
        return $?
    else
        log_debug "Функция '$func_name' не найдена"
        if [[ $DEBUG -eq 1 ]]; then
            friendly_message "developer" "Функция '$func_type' не реализована" "Добавьте: provider_${CURRENT_PROVIDER_TYPE}_${func_type}() { ... }"
        fi
        return 1
    fi
}
# =============================================================================
# УЛУЧШЕННЫЙ СПИННЕР
# =============================================================================
can_use_unicode_spinner() {
    if ! command -v tput >/dev/null; then return 1; fi
    if [[ "$LANG" != *"UTF-8"* && "$LANG" != *"utf-8"* ]]; then return 1; fi
    if [[ ! -t 1 ]]; then return 1; fi
    return 0
}
show_advanced_spinner() {
    local pid=$1 message="$2" delay=0.15
    if can_use_unicode_spinner; then
        local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') i=0
        tput civis 2>/dev/null
        while kill -0 $pid 2>/dev/null; do
            printf "\r[%s] %s" "${spin[i]}" "$message" >&2
            ((i = (i + 1) % ${#spin[@]}))
            sleep $delay
        done
        tput cnorm 2>/dev/null
        printf "\r✅ %s завершено!\n" "$message" >&2
    else
        local spinstr='|/-\' temp
        while kill -0 $pid 2>/dev/null; do
            temp=${spinstr#?}
            printf "\r[%c] %s" "$spinstr" "$message" >&2
            spinstr=$temp${spinstr%"$temp"}
            sleep $delay
        done
        printf "\r✓ %s завершено!\n" "$message" >&2
    fi
}
# =============================================================================
# АНАЛИЗ ЗАВИСИМОСТЕЙ — ИСПРАВЛЕННАЯ ВЕРСИЯ
# =============================================================================
analyze_dependencies() {
    local ingredients="$1" cleanups="$2"
    log_step "Анализ зависимостей рецепта..."
    echo
    local tmp_out="/tmp/chef_deps_$$"
    > "$tmp_out"  # очистить файл

    local analysis_errors=()

    # --- Анализ установки ---
    if [[ -n "$ingredients" ]]; then
        for pkg in $ingredients; do
            [[ -z "$pkg" ]] && continue

            (
                # ВСЁ внутри фонового процесса
                if ! call_provider_func "$CLIENT" "check_install" "$pkg" 2>/dev/null; then
                    echo "ERROR:unavailable:$pkg" >> "$tmp_out"
                    exit 0
                fi
                deps=$(call_provider_func "$CLIENT" "deps_install" "$pkg" 2>/dev/null)
                if [[ -n "$deps" ]]; then
                    for dep in $deps; do
                        if [[ ! " $ingredients " == *" $dep "* ]]; then
                            echo "INSTALL_DEP:$dep" >> "$tmp_out"
                        fi
                    done
                fi
            ) &
            local pid=$!
            show_advanced_spinner $pid "Анализ $pkg"
            wait $pid
        done
    fi

    # --- Анализ удаления ---
    if [[ -n "$cleanups" ]]; then
        for pkg in $cleanups; do
            [[ -z "$pkg" ]] && continue
            (
                if ! call_provider_func "$CLIENT" "check_remove" "$pkg" 2>/dev/null; then
                    echo "ERROR:not_installed:$pkg" >> "$tmp_out"
                    exit 0
                fi
                deps=$(call_provider_func "$CLIENT" "deps_remove" "$pkg" 2>/dev/null)
                if [[ -n "$deps" ]]; then
                    for dep in $deps; do
                        if [[ ! " $cleanups " == *" $dep "* ]]; then
                            echo "REMOVE_DEP:$dep" >> "$tmp_out"
                        fi
                    done
                fi
            ) &
            local pid=$!
            show_advanced_spinner $pid "Анализ удаления $pkg"
            wait $pid
        done
    fi

    # --- Обработка результатов ---
    local missing_install_deps=() additional_remove_deps=()

    while IFS= read -r line; do
        case "$line" in
            ERROR:unavailable:*)
                analysis_errors+=("Пакет '${line#ERROR:unavailable:}' недоступен в репозиториях")
                ;;
            INSTALL_DEP:*)
                missing_install_deps+=("${line#INSTALL_DEP:}")
                ;;
            REMOVE_DEP:*)
                additional_remove_deps+=("${line#REMOVE_DEP:}")
                ;;
        esac
    done < "$tmp_out"
    rm -f "$tmp_out"

    # --- Вывод ---
    echo
    local has_warnings=0
    if [[ ${#analysis_errors[@]} -gt 0 ]]; then
        log_warn "Проблемы с доступностью пакетов:"
        for err in "${analysis_errors[@]}"; do echo "  • $err"; done
        has_warnings=1
    fi
    if [[ ${#missing_install_deps[@]} -gt 0 ]]; then
        log_warn "Для установки потребуются дополнительные ОБЯЗАТЕЛЬНЫЕ зависимости:"
        for dep in $(printf '%s\n' "${missing_install_deps[@]}" | sort -u); do
            echo "  • $dep"
        done
        has_warnings=1
    fi
    if [[ ${#additional_remove_deps[@]} -gt 0 ]]; then
        log_warn "При удалении также будут затронуты пакеты, зависящие от удаляемых:"
        for dep in $(printf '%s\n' "${additional_remove_deps[@]}" | sort -u); do
            echo "  • $dep"
        done
        has_warnings=1
    fi
    if [[ $has_warnings -eq 0 ]]; then
        log_success "Все зависимости учтены в рецепте"
    else
        friendly_message "tip" "Проверьте, ожидали ли вы эти зависимости"
        echo
    fi
    return $has_warnings
}
# =============================================================================
# РАБОТА С ПАКЕТАМИ
# =============================================================================
run_with_privileges() {
    if [[ $EUID -eq 0 ]]; then
        log_detail "Выполнение от root: $*"
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        log_detail "Выполнение через sudo: $*"
        sudo "$@"
    else
        log_error "Требуются права root, но sudo недоступен"
        friendly_message "help" "Запустите скрипт от root" "su - # затем cd $(pwd)"
        exit 1
    fi
}
install_packages() {
    local pkgs="$1"
    [[ -z "$pkgs" ]] && { log_info "Нет пакетов для установки"; return 0; }
    log_step "Установка пакетов: $pkgs"
    local all_install_pkgs="$pkgs"
    for pkg in $pkgs; do
        [[ -z "$pkg" ]] && continue
        local deps
        deps="$(call_provider_func "$CLIENT" "deps_install" "$pkg")"
        for dep in $deps; do
            if [[ ! " $all_install_pkgs " == *" $dep "* ]]; then
                all_install_pkgs="$all_install_pkgs $dep"
                log_detail "Добавлена зависимость: $dep"
            fi
        done
    done
    local pm cmd
    pm="$(get_provider_field "$CLIENT" pkgmgr)"
    cmd="$(get_provider_field "$CLIENT" install)"
    if [[ -z "$pm" || -z "$cmd" ]]; then
        log_error "Не удалось определить команду установки"
        return 1
    fi
    friendly_message "tip" "Начинается установка пакетов..."
    if run_with_privileges "$pm" $cmd $all_install_pkgs; then
        log_success "Пакеты установлены успешно"
        return 0
    else
        log_error "Ошибка при установке пакетов"
        friendly_message "help" "Проверьте:" "• Доступность репозиториев • Имена пакетов • Сетевые настройки"
        return 1
    fi
}
remove_packages() {
    local pkgs="$1"
    [[ -z "$pkgs" ]] && { log_info "Нет пакетов для удаления"; return 0; }
    log_step "Удаление пакетов: $pkgs"
    local all_remove_pkgs="$pkgs"
    for pkg in $pkgs; do
        [[ -z "$pkg" ]] && continue
        local deps
        deps="$(call_provider_func "$CLIENT" "deps_remove" "$pkg")"
        for dep in $deps; do
            if [[ ! " $all_remove_pkgs " == *" $dep "* ]]; then
                all_remove_pkgs="$all_remove_pkgs $dep"
                log_detail "Добавлена зависимость удаления: $dep"
            fi
        done
    done
    local important_pkgs=("sudo" "bash" "coreutils" "systemd")
    for important in "${important_pkgs[@]}"; do
        if [[ " $all_remove_pkgs " == *" $important "* ]]; then
            log_warn "ВНИМАНИЕ: Попытка удаления важного системного пакета: $important"
            friendly_message "tip" "Удаление системных пакетов может привести к неработоспособности системы!"
            read -rp "Продолжить удаление? (y/N): " -n 1
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "Удаление отменено"; return 0; }
            break
        fi
    done
    local pm cmd
    pm="$(get_provider_field "$CLIENT" pkgmgr)"
    cmd="$(get_provider_field "$CLIENT" remove)"
    if run_with_privileges "$pm" $cmd $all_remove_pkgs; then
        log_success "Пакеты удалены успешно"
        return 0
    else
        log_error "Ошибка при удалении пакетов"
        return 1
    fi
}
# =============================================================================
# КОМАНДЫ
# =============================================================================
# ... (остальные функции: detect_client, choose_editor, find_recipe_file, validate_recipe_file,
#      load_recipes, cmd_list, cmd_edit, cmd_cook, cmd_devinfo, main — остаются БЕЗ ИЗМЕНЕНИЙ)
# =============================================================================
# ОСТАЛЬНЫЕ ФУНКЦИИ (БЕЗ ИЗМЕНЕНИЙ)
# =============================================================================
detect_client() {
    log_step "Определение вашего дистрибутива Linux..."
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        CLIENT="${ID,,}"
        if [[ -n "${DISTRO_MAPPING[$CLIENT]}" ]]; then
            local distro_name="${PROVIDER_CONFIGS[${DISTRO_MAPPING[$CLIENT]}:name]}"
            log_success "Определен: $PRETTY_NAME"
            log_detail "Идентификатор: $CLIENT, Пакетный менеджер: $distro_name"
        else
            log_warn "Дистрибутив '$CLIENT' обнаружен, но не зарегистрирован"
            friendly_message "tip" "Вы можете легко добавить поддержку этого дистрибутива"
        fi
    else
        log_error "Не удалось определить дистрибутив"
        exit 1
    fi
}
choose_editor() {
    log_debug "Подбор текстового редактора..."
    local editors=("nano" "mcedit" "vim" "vi")
    for e in "${editors[@]}"; do
        if command -v "$e" >/dev/null 2>&1; then
            EDITOR="$e"
            log_detail "Выбран редактор: $EDITOR"
            if [[ "$e" == "nano" ]]; then
                friendly_message "tip" "Nano - простой редактор. Ctrl+X для выхода, Ctrl+O для сохранения"
            elif [[ "$e" == "mcedit" ]]; then
                friendly_message "tip" "MCEdit - функциональный редактор. F2 - сохранить, F10 - выйти"
            fi
            return
        fi
    done
    EDITOR="${VISUAL:-${EDITOR:-vi}}"
    log_warn "Используется системный редактор по умолчанию: $EDITOR"
}
find_recipe_file() {
    log_step "Поиск книги рецептов для '$CLIENT'..."
    local pattern="*${CLIENT}*.inf"
    local candidates=()
    for path in "${RECIPE_PATHS[@]}"; do
        [[ -d "$path" ]] || continue
        log_debug "Поиск в: $path"
        while IFS= read -rd '' file; do
            candidates+=("$file")
            log_debug "Найдена книга: $(basename "$file")"
        done < <(find "$path" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null)
    done
    if [[ ${#candidates[@]} -eq 0 ]]; then
        log_warn "Специализированная книга для '$CLIENT' не найдена"
        handle_missing_recipe
        return 1
    elif [[ ${#candidates[@]} -eq 1 ]]; then
        RECIPE_FILE="${candidates[0]}"
        log_success "Найдена книга: $(basename "$RECIPE_FILE")"
        return 0
    else
        log_info "Найдено несколько подходящих книг:"
        select_from_list "Выберите книгу рецептов:" "${candidates[@]}"
        if [[ $SELECTED -ne 255 ]]; then
            RECIPE_FILE="${candidates[$((SELECTED-1))]}"
            log_detail "Выбрана книга: $(basename "$RECIPE_FILE")"
            return 0
        else
            log_error "Книга не выбрана"
            return 1
        fi
    fi
}
handle_missing_recipe() {
    log_step "Поиск альтернативных книг рецептов..."
    local all_books=()
    for path in "${RECIPE_PATHS[@]}"; do
        [[ -d "$path" ]] || continue
        while IFS= read -rd '' file; do
            all_books+=("$file")
        done < <(find "$path" -maxdepth 1 -name "*.inf" -type f -print0 2>/dev/null)
    done
    if [[ ${#all_books[@]} -gt 0 ]]; then
        log_info "Найдены другие книги рецептов:"
        select_from_list "Можно использовать как основу:" "${all_books[@]}"
        if [[ $SELECTED -ne 255 ]]; then
            local selected_book="${all_books[$((SELECTED-1))]}"
            friendly_message "help" "Открываю книгу для адаптации" "Сохраните как '${CLIENT}.inf'"
            edit_recipe "$selected_book"
            exit 0
        fi
    fi
    friendly_message "help" "Создаю новую книгу рецептов" "Вы можете сразу её отредактировать"
    create_new_recipe
    exit 0
}
select_from_list() {
    local header="$1"; shift
    local items=("$@")
    [[ -n "$header" ]] && log_info "$header"
    for i in "${!items[@]}"; do
        echo "  $((i+1)). $(basename "${items[$i]}")"
    done
    echo -e "${CYAN}  0. Отмена${NC}"
    read -rp "Выберите вариант [0-${#items[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
        SELECTED="$choice"
    elif [[ "$choice" == "0" ]]; then
        SELECTED=255
        log_info "Выбор отменен"
    else
        log_error "Неверный выбор: '$choice'"
        SELECTED=255
    fi
}
create_new_recipe() {
    local recipes_dir="${RECIPE_PATHS[0]}"
    log_step "Создание новой книги рецептов..."
    mkdir -p "$recipes_dir"
    local new_file="$recipes_dir/${CLIENT}.inf"
    cat > "$new_file" <<EOF
# Книга рецептов для: ${CLIENT^^}
# Создано: $(date "+%Y-%m-%d %H:%M:%S")
# Автор: $(whoami)
[mc]
name = mc
ingredients = mc
cleanups =
spices = После установки:
[sudo]
name = Настройка sudo
ingredients = sudo
cleanups =
spices = Добавьте пользователя в группу sudo
         sudo usermod -a -G sudo username
EOF
    if [[ -f "$new_file" ]]; then
        log_success "Создана книга: $new_file"
        friendly_message "tip" "Книга создана с примерными рецептами. Отредактируйте её под свои нужды."
        edit_recipe "$new_file"
    else
        log_error "Не удалось создать файл: $new_file"
        exit 1
    fi
}
edit_recipe() {
    choose_editor
    if ! command -v "$EDITOR" >/dev/null 2>&1; then
        log_error "Редактор '$EDITOR' не найден"
        friendly_message "help" "Установите редактор или задайте переменную EDITOR" "apt-get install nano"
        return 1
    fi
    log_step "Открываю книгу рецептов..."
    log_detail "Используется: $EDITOR $1"
    friendly_message "tip" "После редактирования сохраните файл и закройте редактор"
    "$EDITOR" "$1"
}
validate_recipe_file() {
    log_step "Проверка целостности книги рецептов..."
    if [[ ! -f "$RECIPE_FILE" ]]; then
        log_error "Файл не найден: $RECIPE_FILE"
        return 1
    fi
    local line_num=0 in_section=0 section_name=""
    local has_name=0 has_ingredients=0 has_cleanups=0 has_spices=0
    local validation_errors=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
            if ((in_section)) && (( !has_name )); then
                validation_errors+=("Строка $line_num: Секция '$section_name' без поля 'name'")
            fi
            section_name="${BASH_REMATCH[1]}"
            in_section=1
            has_name=0; has_ingredients=0; has_cleanups=0; has_spices=0
            log_debug "Начало секции: $section_name"
            continue
        fi
        if (( !in_section )); then
            validation_errors+=("Строка $line_num: Данные вне секции: '$line'")
            continue
        fi
        if [[ "$line" =~ ^name[[:space:]]*=[[:space:]]*(.*) ]]; then
            has_name=1
        elif [[ "$line" =~ ^ingredients[[:space:]]*=[[:space:]]*(.*) ]]; then
            has_ingredients=1
        elif [[ "$line" =~ ^cleanups[[:space:]]*=[[:space:]]*(.*) ]]; then
            has_cleanups=1
        elif [[ "$line" =~ ^spices[[:space:]]*=[[:space:]]*(.*) ]]; then
            has_spices=1
        elif [[ "$line" =~ ^[[:space:]]+ ]] && ((has_spices)); then
            continue
        else
            validation_errors+=("Строка $line_num: Неизвестное поле в секции '$section_name': '$line'")
        fi
    done < "$RECIPE_FILE"
    if ((in_section)) && (( !has_name )); then
        validation_errors+=("Конец файла: Секция '$section_name' без поля 'name'")
    fi
    if [[ ${#validation_errors[@]} -eq 0 ]]; then
        log_success "Книга рецептов прошла проверку"
        log_detail "Файл: $(basename "$RECIPE_FILE")"
        return 0
    else
        log_error "Найдены ошибки в книге рецептов:"
        for error in "${validation_errors[@]}"; do
            echo "  • $error"
        done
        friendly_message "help" "Исправьте ошибки в редакторе" "Запустите: $0 edit"
        return 1
    fi
}
load_recipes() {
    log_debug "Загрузка рецептов в память..."
    local current_section="" spices_lines=() in_spices=0
    RECIPE_NAME=() RECIPE_INGREDIENTS=() RECIPE_CLEANUPS=() RECIPE_SPICES=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
            [[ -n "$current_section" ]] && RECIPE_SPICES["$current_section"]=$(IFS=$'\n'; echo "${spices_lines[*]}")
            current_section="${BASH_REMATCH[1]}"
            spices_lines=()
            in_spices=0
            log_debug "Загружается рецепт: $current_section"
            continue
        fi
        if [[ "$line" =~ ^name[[:space:]]*=[[:space:]]*(.*) ]]; then
            RECIPE_NAME["$current_section"]="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^ingredients[[:space:]]*=[[:space:]]*(.*) ]]; then
            RECIPE_INGREDIENTS["$current_section"]="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^cleanups[[:space:]]*=[[:space:]]*(.*) ]]; then
            RECIPE_CLEANUPS["$current_section"]="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^spices[[:space:]]*=[[:space:]]*(.*) ]]; then
            spices_lines=("${BASH_REMATCH[1]}")
            in_spices=1
        elif ((in_spices)) && [[ "$line" =~ ^[[:space:]]+ ]]; then
            spices_lines+=("$line")
        fi
    done < "$RECIPE_FILE"
    [[ -n "$current_section" ]] && RECIPE_SPICES["$current_section"]=$(IFS=$'\n'; echo "${spices_lines[*]}")
    log_success "Загружено рецептов: ${#RECIPE_NAME[@]}"
}
find_matching_recipes() {
    local query="$1"
    FOUND_RECIPES=()
    log_debug "Поиск рецептов по запросу: '$query'"
    for key in "${!RECIPE_NAME[@]}"; do
        if [[ "${RECIPE_NAME[$key],,}" == *"${query,,}"* ]] || [[ "${key,,}" == *"${query,,}"* ]]; then
            FOUND_RECIPES["$key"]="$key"
            log_debug "Найден рецепт: $key -> ${RECIPE_NAME[$key]}"
        fi
    done
}
cmd_list() {
    local search="$1"
    if ! find_recipe_file; then return 1; fi
    if ! validate_recipe_file; then
        friendly_message "help" "Сначала исправьте ошибки в книге" "$0 edit"
        return 1
    fi
    load_recipes
    find_matching_recipes "$search"
    if [[ ${#FOUND_RECIPES[@]} -gt 0 ]]; then
        log_success "Найдено рецептов: ${#FOUND_RECIPES[@]}"
        echo
        for r in "${!FOUND_RECIPES[@]}"; do
            echo -e "  ${GREEN}•${NC} ${RECIPE_NAME[$r]} ${CYAN}[$r]${NC}"
            [[ -n "${RECIPE_INGREDIENTS[$r]}" ]] && echo "      📦 Установка: ${RECIPE_INGREDIENTS[$r]}"
            [[ -n "${RECIPE_CLEANUPS[$r]}" ]] && echo "      🧹 Очистка: ${RECIPE_CLEANUPS[$r]}"
            echo
        done
    else
        log_info "Рецепты не найдены"
        friendly_message "tip" "Попробуйте другой поисковый запрос или создайте новый рецепт"
    fi
}
cmd_edit() {
    if find_recipe_file; then
        edit_recipe "$RECIPE_FILE"
    else
        log_error "Не удалось найти книгу для редактирования"
        return 1
    fi
}
cmd_validate() {
    if find_recipe_file; then
        validate_recipe_file
    else
        return 1
    fi
}
cmd_cook() {
    local query="$1"
    [[ -z "$query" ]] && {
        log_error "Укажите название рецепта"
        friendly_message "help" "Посмотрите доступные рецепты" "$0 list"
        exit 1
    }
    log_step "Подготовка к приготовлению: '$query'"
    if ! find_recipe_file; then exit 1; fi
    if ! validate_recipe_file; then
        log_error "Невозможно работать с книгой, содержащей ошибки"
        exit 1
    fi
    load_recipes
    find_matching_recipes "$query"
    if [[ ${#FOUND_RECIPES[@]} -eq 0 ]]; then
        log_error "Рецепт '$query' не найден"
        friendly_message "help" "Используйте 'list' для просмотра всех рецептов" "$0 list"
        exit 1
    elif [[ ${#FOUND_RECIPES[@]} -gt 1 ]]; then
        log_info "Найдено несколько рецептов:"
        local i=1 keys=()
        for k in "${!FOUND_RECIPES[@]}"; do
            echo "  $i. ${RECIPE_NAME[$k]} ${CYAN}[$k]${NC}"
            keys+=("$k")
            ((i++))
        done
        read -rp "Выберите рецепт [1-${#keys[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#keys[@]} )); then
            query="${keys[$((choice-1))]}"
            log_detail "Выбран рецепт: ${RECIPE_NAME[$query]}"
        else
            log_info "Приготовление отменено"
            exit 0
        fi
    else
        query="${!FOUND_RECIPES[@]}"
        log_detail "Выбран рецепт: ${RECIPE_NAME[$query]}"
    fi
    local name="${RECIPE_NAME[$query]}"
    local ing="${RECIPE_INGREDIENTS[$query]}"
    local clean="${RECIPE_CLEANUPS[$query]}"
    local spice="${RECIPE_SPICES[$query]}"
    log_info "Рецепт: '$name'"
    if ! analyze_dependencies "$ing" "$clean"; then
        read -rp "Продолжить приготовление? (y/N): " -n 1
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "Приготовление отменено"; exit 0; }
    fi
    if [[ -n "$spice" ]]; then
        log_info "Специи:"
        echo "$spice" | while IFS= read -r l; do echo "  $l"; done
    fi
    read -rp "Начать приготовление? (y = готовить, e = редактировать, n = отмена): " -n 1
    echo
    case "$REPLY" in
        [eE]) edit_recipe "$RECIPE_FILE"; exit 0;;
        [nN]) log_info "Отменено."; exit 0;;
    esac
    if [[ -n "$clean" ]]; then remove_packages "$clean"; fi
    if [[ -n "$ing" ]]; then install_packages "$ing"; fi
    log_success "Рецепт '$name' приготовлен!"
    if [[ -n "$spice" ]]; then
        log_info "Напоминание:"
        echo "$spice" | while IFS= read -r l; do echo "  $l"; done
    fi
    log_info "Приятного аппетита! 🍽️"
}
cmd_devinfo() {
    echo; friendly_message "developer" "Информация о системе для разработчиков"; echo
    detect_client
    echo -e "${CYAN}Информация о дистрибутиве:${NC}"
    echo "  ID: $CLIENT"
    echo "  Тип пакетного менеджера: ${DISTRO_MAPPING[$CLIENT]:-НЕ ЗАРЕГИСТРИРОВАН}"
    echo "  Поддерживается: $([[ -n "${DISTRO_MAPPING[$CLIENT]}" ]] && echo "ДА" || echo "НЕТ")"
    if [[ -n "${DISTRO_MAPPING[$CLIENT]}" ]]; then
        echo; echo -e "${CYAN}Конфигурация провайдера:${NC}"
        local provider_type="${DISTRO_MAPPING[$CLIENT]}"
        for key in "${!PROVIDER_CONFIGS[@]}"; do
            if [[ "$key" == "$provider_type:"* ]]; then
                local field="${key#$provider_type:}"
                echo "  $field: ${PROVIDER_CONFIGS[$key]}"
            fi
        done
        echo; echo -e "${CYAN}Проверка функций:${NC}"
        local funcs=("check_install" "check_remove" "deps_install" "deps_remove")
        for func in "${funcs[@]}"; do
            local func_name="provider_${provider_type}_${func}"
            if declare -f "$func_name" >/dev/null; then
                echo "  ✅ $func_name"
            else
                echo "  ❌ $func_name"
            fi
        done
    else
        echo; show_distro_help
    fi
    echo; echo -e "${CYAN}Существующие дистрибутивы:${NC}"
    for distro in "${!DISTRO_MAPPING[@]}"; do
        if [[ "$distro" == "$CLIENT" ]]; then
            echo "  🟢 $distro → ${DISTRO_MAPPING[$distro]}"
        else
            echo "  🔵 $distro → ${DISTRO_MAPPING[$distro]}"
        fi
    done
}
main() {
    init_providers
    register_providers
    friendly_message "welcome"
    detect_client
    if ! detect_provider; then exit 1; fi
    choose_editor
    local cmd="${1:-help}"
    case "$cmd" in
        list)     cmd_list "$2" ;;
        cook)     cmd_cook "$2" ;;
        edit)     cmd_edit ;;
        validate) cmd_validate ;;
        devinfo)  cmd_devinfo ;;
        help)     show_help ;;
        *)        log_error "Неизвестная команда: $cmd"; show_help; exit 1 ;;
    esac
}
show_help() {
    cat <<EOF
${PROGRAM_NAME} v${VERSION} — управление рецептами (.inf)
Использование: $0 <команда> [аргумент]
Основные команды:
  list [поиск]   — показать рецепты
  cook <рецепт>  — приготовить рецепт
  edit           — редактировать книгу
  validate       — проверить книгу
Команды для разработчиков:
  devinfo        — показать информацию о системе
  help           — эта справка
Примеры:
  $0 list                    # Все рецепты
  $0 cook steam             # Приготовить рецепт
  $0 devinfo                # Информация для разработки
💡 Подсказка: Хотите добавить свой дистрибутив? Используйте 'devinfo'!
EOF
}
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
