#!/usr/bin/env bash
# Espera o nice!nano entrar em modo UF2, grava o firmware e CONFIRMA o resultado.
#
# Diferencas para o `flash_sofle.sh`:
#   - nao depende do automount do desktop; monta o disco via udisksctl
#   - nao pergunta nada: fica esperando ate o duplo-reset acontecer
#   - o veredito vem do kernel (a placa virou teclado?), nao do `cp`
#
# O `cp` quase sempre retorna erro aqui, porque o bootloader reinicia a placa
# assim que termina de receber o arquivo e o destino some no meio da copia.
# Por isso ele nao serve como prova de sucesso.
#
# Uso:
#   ./scripts/flash_sofle_watch.sh left            # pega o .uf2 mais recente
#   ./scripts/flash_sofle_watch.sh right
#   ./scripts/flash_sofle_watch.sh left ARQ.uf2    # .uf2 especifico
set -uo pipefail

FW_DIR="${SOFLE_FW_DIR:-$HOME/Downloads/sofle-abnt2}"
TIMEOUT="${SOFLE_FLASH_TIMEOUT:-1800}"

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m"

SIDE="${1:-left}"
case "$SIDE" in
  left|right) ;;
  *) echo -e "${RED}Lado invalido: ${SIDE}. Use 'left' ou 'right'.${NC}"; exit 1 ;;
esac

UF2="${2:-}"
if [ -z "$UF2" ]; then
  UF2=$(ls -t "${FW_DIR}/sofle_${SIDE}"*.uf2 2>/dev/null | head -1)
fi
[ -n "$UF2" ] && [ -f "$UF2" ] || {
  echo -e "${RED}Nenhum .uf2 do lado '${SIDE}' em ${FW_DIR}.${NC}"
  echo "Rode ./scripts/build_sofle.sh antes."
  exit 1
}

# Ponto de montagem que o desktop ja tenha montado sozinho.
find_mounted() {
  for root in "/media/$USER" "/run/media/$USER" /media /mnt; do
    [ -d "$root" ] || continue
    for dir in "$root"/*/ "$root"/*/*/; do
      [ -d "$dir" ] || continue
      if [ -e "${dir}INFO_UF2.TXT" ] || [ -e "${dir}CURRENT.UF2" ]; then
        echo "${dir%/}"; return 0
      fi
    done
  done
  return 1
}

# Dispositivo de bloco do bootloader, montado ou nao.
find_device() {
  lsblk -rno NAME,LABEL,MODEL 2>/dev/null | while read -r name label model; do
    case "${label}${model}" in
      *NICENANO*|*NICE*NANO*|*UF2*|*nRF*) echo "/dev/$name"; return 0 ;;
    esac
  done
  return 1
}

echo -e "${YELLOW}==> firmware:${NC} $(basename "$UF2")"
echo -e "${YELLOW}==> conecte a metade ${SIDE} e de o duplo-reset.${NC}"
echo -e "${YELLOW}    quando o LED azul PULSAR, nao toque em mais nada.${NC}"
echo "Aguardando ate ${TIMEOUT}s..."

deadline=$((SECONDS + TIMEOUT))
mount=""
while [ $SECONDS -lt $deadline ]; do
  mount=$(find_mounted) || mount=""

  if [ -z "$mount" ] && dev=$(find_device) && [ -n "$dev" ]; then
    echo -e "${YELLOW}Disco do bootloader em ${dev}; montando...${NC}"
    out=$(udisksctl mount -b "$dev" --no-user-interaction 2>&1)
    echo "$out"
    mount=$(echo "$out" | grep -oP '(?<=at )\S+' | tr -d '.')
    [ -d "${mount:-}" ] || mount=$(find_mounted) || mount=""
  fi

  [ -n "${mount:-}" ] && [ -d "$mount" ] && break
  sleep 0.3
  mount=""
done

[ -n "${mount:-}" ] || { echo -e "${RED}Timeout: o modo UF2 nao apareceu.${NC}"; exit 1; }

echo -e "${GREEN}Montado em: ${mount}${NC}"
grep -i model "$mount/INFO_UF2.TXT" 2>/dev/null || true

cp_status=0
cp "$UF2" "$mount"/ 2>&1 || cp_status=$?
sync 2>/dev/null
echo "Copia terminada (status ${cp_status}). Aguardando a placa reiniciar..."
sleep 10

echo -e "${YELLOW}--- o que o kernel viu ---${NC}"
journalctl -k --since '-40 s' --no-pager 2>/dev/null \
  | grep -iE 'Manufacturer:|Product:|no interfaces|input:.*[Kk]eyboard' || true

if grep -qi sofle /proc/bus/input/devices 2>/dev/null; then
  echo -e "${GREEN}SUCESSO: a placa subiu como teclado.${NC}"
  grep '^N: Name' /proc/bus/input/devices | grep -i sofle
  exit 0
fi

echo -e "${RED}ATENCAO: a placa ainda nao aparece como teclado.${NC}"
echo "Sintomas que importam nas linhas acima:"
echo "  'Product: Sofle'              -> subiu certo, so demorou"
echo "  'config 1 has no interfaces?' -> firmware sem HID USB"
echo "  'Product: nice!nano'          -> voltou ao bootloader; nao inicia"
exit 2
