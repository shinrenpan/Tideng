#!/usr/bin/env bash
# 驗證容器裡的 Siming 真的載入了 terminology，而不只是「起得來」。
#
# 為什麼需要這個：Siming 的 packages/*.tgz 是 gitignored。從乾淨 clone 或 CI
# 建置會得到空的 packages 目錄，而 server 仍會正常啟動、/health 仍回 200、
# 每個 endpoint 都可連線——只有 terminology 靜默消失。
#
# 實測 CapabilityStatement 的大小：
#   有 packages   76,643 bytes（1088 CodeSystems / 1230 extensional ValueSets）
#   空 packages   11,488 bytes
# 差 6.7 倍，長度斷言就夠靈敏，不需要比對內容。
set -euo pipefail

BASE="${1:-http://localhost:${FHIR_PORT:-8080}}"
# 門檻取兩個實測值之間，且離兩邊都遠——IG 版本變動不會誤觸，terminology 消失一定觸發。
MIN_BYTES=40000

echo "檢查 ${BASE}/metadata …"
bytes=$(curl -fsS "${BASE}/metadata" | wc -c | tr -d ' ')

if [ "$bytes" -lt "$MIN_BYTES" ]; then
  echo "✘ CapabilityStatement 只有 ${bytes} 位元組（門檻 ${MIN_BYTES}）"
  echo ""
  echo "  幾乎可以確定是 build context 裡的 packages/*.tgz 不存在。"
  echo "  server 會照常運作，但 terminology 是空的。"
  echo "  確認 \${SIMING_PATH:-../../Siming}/packages/ 裡有 .tgz 檔，然後："
  echo "      docker-compose build --no-cache siming"
  exit 1
fi

echo "✔ CapabilityStatement ${bytes} 位元組，terminology 已載入"
