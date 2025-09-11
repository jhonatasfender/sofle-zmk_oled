#!/usr/bin/env bash
set -euo pipefail

# Script para copiar os UF2s compilados do Sofle (ZMK) para o NICENANO.
#
# Uso rápido:
#   ./scripts/flash_sofle.sh           # Flasha esquerda e direita (nesta ordem)
#   ./scripts/flash_sofle.sh left      # Somente esquerda (posicional)
#   ./scripts/flash_sofle.sh right     # Somente direita (posicional)
#   ./scripts/flash_sofle.sh --left    # Somente esquerda (flag)
#   ./scripts/flash_sofle.sh --right   # Somente direita (flag)
#   ./scripts/flash_sofle.sh left  /caminho/custom.uf2   # UF2 customizado
#   ./scripts/flash_sofle.sh right /caminho/custom.uf2   # UF2 customizado
#   ./scripts/flash_sofle.sh --left /caminho/custom.uf2  # UF2 customizado
#   ./scripts/flash_sofle.sh --right /caminho/custom.uf2 # UF2 customizado
#
# Dica: coloque a metade a ser flashada em modo UF2 (duplo clique no reset)
# e monte a unidade USB. Se copiar falhar com "No space left on device",
# remonte e tente novamente apenas aquela metade.

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
LEFT_DEFAULT_UF2="${PROJECT_ROOT}/build/left/zephyr/zmk.uf2"
RIGHT_DEFAULT_UF2="${PROJECT_ROOT}/build/right/zephyr/zmk.uf2"

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m"

usage() {
  cat <<EOF
Uso:
  $(basename "$0") [left [ARQ.uf2]] [right [ARQ.uf2]]
  $(basename "$0") [--left [ARQ.uf2]] [--right [ARQ.uf2]]

Sem argumentos, flasha esquerda e direita usando:
  - Esquerda: ${LEFT_DEFAULT_UF2}
  - Direita : ${RIGHT_DEFAULT_UF2}

Opções:
  left [ARQ.uf2]     Flasha somente a esquerda (opcionalmente com UF2 específico)
  right [ARQ.uf2]    Flasha somente a direita (opcionalmente com UF2 específico)
  --left [ARQ.uf2]   Flasha somente a esquerda (opcionalmente com UF2 específico)
  --right [ARQ.uf2]  Flasha somente a direita (opcionalmente com UF2 específico)
  -h, --help         Mostra esta ajuda
EOF
}

# Retorna (em stdout) uma lista de possíveis pontos de montagem UF2 (um por linha)
find_uf2_mounts() {
  local roots=("/media/$USER" "/run/media/$USER" "/mnt" "/media" "/Volumes")
  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue
    # Procura marcadores típicos do boot UF2
    find "$root" -maxdepth 2 -mindepth 1 -type d 2>/dev/null \
      -exec test -e '{}/INFO_UF2.TXT' -o -e '{}/CURRENT.UF2' ';' -print || true
  done | sort -u
}

human_side() {
  case "$1" in
    left) echo "esquerda";;
    right) echo "direita";;
    *) echo "$1";;
  esac
}

select_mount_interactive() {
  local mounts=()
  while IFS= read -r line; do mounts+=("$line"); done < <(find_uf2_mounts)

  if [ ${#mounts[@]} -eq 0 ]; then
    return 1
  elif [ ${#mounts[@]} -eq 1 ]; then
    echo "${mounts[0]}"
    return 0
  else
    echo -e "${YELLOW}Foram encontradas múltiplas unidades UF2:${NC}"
    local i
    for ((i=0; i<${#mounts[@]}; i++)); do
      echo "  [$i] ${mounts[$i]}"
    done
    local choice
    read -rp "Selecione o índice da unidade: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -lt ${#mounts[@]} ]; then
      echo "${mounts[$choice]}"
      return 0
    else
      echo -e "${RED}Índice inválido.${NC}" >&2
      return 1
    fi
  fi
}

flash_one() {
  local side="$1"; shift
  local uf2_path="$1"; shift

  if [ ! -f "$uf2_path" ]; then
    echo -e "${RED}UF2 não encontrado:${NC} $uf2_path"
    exit 1
  fi

  echo -e "${YELLOW}Conecte a metade $(human_side "$side") em modo UF2 e pressione Enter...${NC}"
  read -r _

  local mount
  mount=$(select_mount_interactive || true)
  if [ -z "${mount:-}" ]; then
    echo -e "${RED}Nenhuma unidade UF2 detectada. Verifique o modo UF2 e tente novamente.${NC}"
    exit 1
  fi

  echo -e "${GREEN}Copiando $(basename "$uf2_path") para ${mount}${NC}"
  if ! cp -v "$uf2_path" "$mount"/; then
    echo -e "${RED}Falha ao copiar. Se aparecer 'No space left on device', remonte o NICENANO em modo UF2 e tente novamente apenas esta metade.${NC}"
    exit 1
  fi
  sync
  echo -e "${GREEN}Concluído: metade $(human_side "$side").${NC}\n"
}

# Parse de argumentos
DO_LEFT=1; DO_RIGHT=1
LEFT_UF2="$LEFT_DEFAULT_UF2"
RIGHT_UF2="$RIGHT_DEFAULT_UF2"

if [ $# -gt 0 ]; then
  DO_LEFT=0; DO_RIGHT=0
  while [ $# -gt 0 ]; do
    case "$1" in
      left)
        DO_LEFT=1
        if [ "${2-}" ] && [[ ! "$2" =~ ^-- ]] && [[ ! "$2" =~ ^(left|right)$ ]]; then
          LEFT_UF2="$2"; shift
        fi
        ;;
      right)
        DO_RIGHT=1
        if [ "${2-}" ] && [[ ! "$2" =~ ^-- ]] && [[ ! "$2" =~ ^(left|right)$ ]]; then
          RIGHT_UF2="$2"; shift
        fi
        ;;
      --left)
        DO_LEFT=1
        if [ "${2-}" ] && [[ ! "$2" =~ ^-- ]]; then
          LEFT_UF2="$2"; shift
        fi
        ;;
      --right)
        DO_RIGHT=1
        if [ "${2-}" ] && [[ ! "$2" =~ ^-- ]]; then
          RIGHT_UF2="$2"; shift
        fi
        ;;
      -h|--help)
        usage; exit 0
        ;;
      *)
        echo -e "${RED}Argumento desconhecido:${NC} $1" >&2
        usage; exit 1
        ;;
    esac
    shift
  done
fi

if [ "$DO_LEFT" -eq 1 ]; then
  flash_one left "$LEFT_UF2"
fi

if [ "$DO_RIGHT" -eq 1 ]; then
  flash_one right "$RIGHT_UF2"
fi

echo -e "${GREEN}Tudo pronto!${NC}"


