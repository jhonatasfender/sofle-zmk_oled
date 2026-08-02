#!/usr/bin/env bash
# Compila o firmware no GitHub Actions e baixa os .uf2.
#
# Este projeto nao tem ambiente de build local (nao ha west/zephyr na maquina):
# quem compila e o workflow `build.yml`, que roda o build-user-config do ZMK.
# O script dispara esse workflow, espera terminar e traz os artefatos.
#
# Uso:
#   ./scripts/build_sofle.sh              # branch atual
#   ./scripts/build_sofle.sh minha-branch # branch especifica
#
# Requer o `gh` autenticado (gh auth status).
set -uo pipefail

REPO="${SOFLE_REPO:-jhonatasfender/sofle-zmk_oled}"
DEST="${SOFLE_FW_DIR:-$HOME/Downloads/sofle-abnt2}"

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m"

BRANCH="${1:-$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --abbrev-ref HEAD 2>/dev/null)}"
[ -n "$BRANCH" ] || { echo -e "${RED}Nao consegui descobrir a branch.${NC}"; exit 1; }

echo -e "${YELLOW}==> disparando build da branch ${BRANCH}${NC}"
gh workflow run build.yml --repo "$REPO" --ref "$BRANCH" || exit 1

# O run demora alguns segundos para aparecer na API depois do dispatch.
sleep 25

run_id=$(gh run list --repo "$REPO" --branch "$BRANCH" --limit 1 \
           --json databaseId --jq '.[0].databaseId')
[ -n "$run_id" ] || { echo -e "${RED}Nenhum run encontrado para ${BRANCH}.${NC}"; exit 1; }
echo -e "${YELLOW}==> run ${run_id}${NC}  https://github.com/${REPO}/actions/runs/${run_id}"

while :; do
  status=$(gh run view "$run_id" --repo "$REPO" --json status,conclusion \
             --jq '"\(.status) \(.conclusion)"')
  case "$status" in
    completed*) echo; echo -e "${YELLOW}==> ${status}${NC}"; break ;;
  esac
  printf '.'
  sleep 20
done

case "$status" in
  *success*) ;;
  *) echo -e "${RED}==> BUILD FALHOU.${NC} Veja o log:"
     echo "    gh run view ${run_id} --repo ${REPO} --log-failed"
     exit 1 ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gh run download "$run_id" --repo "$REPO" -D "$tmp" || exit 1

mkdir -p "$DEST"
find "$tmp" -name '*.uf2' -print0 | xargs -0 -I{} cp {} "$DEST"/
echo -e "${GREEN}==> firmware em ${DEST}:${NC}"
ls -la "$DEST"
