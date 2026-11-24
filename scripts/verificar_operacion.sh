#!/bin/sh
# Operación de ejemplo del proyecto: calcula el total de un pedido contra la API, que a su vez
# valida las existencias en PostgreSQL (usa los dos contenedores).
# Termina con código 1 si la respuesta no es la esperada, lo que hace fallar la construcción.
#
# Uso: scripts/verificar_operacion.sh <red-docker> [total-esperado]
#   red-docker      red de Compose donde está el servicio "api" (p. ej. orders-ci-12_default)
#   total-esperado  por defecto 144000.00
set -eu

NETWORK="${1:?Indique la red de Docker Compose}"
EXPECTED_TOTAL="${2:-144000.00}"
CURL_IMAGE="curlimages/curl:8.11.1"
BODY='{"items":[{"sku":"RICE","quantity":2,"unitPrice":50000},{"sku":"OIL","quantity":3,"unitPrice":20000}],"discountPercentage":10}'

echo "POST http://api:8080/api/orders/total"
echo "Pedido: $BODY"

RESPONSE=$(docker run --rm --network "$NETWORK" "$CURL_IMAGE" \
  -s -w '\n%{http_code}' -X POST http://api:8080/api/orders/total \
  -H 'Content-Type: application/json' -d "$BODY")

HTTP_CODE=$(printf '%s\n' "$RESPONSE" | tail -n 1)
JSON=$(printf '%s\n' "$RESPONSE" | sed '$d')

echo "Respuesta HTTP $HTTP_CODE: $JSON"

if [ "$HTTP_CODE" = "200" ] && printf '%s' "$JSON" | grep -q "\"total\":${EXPECTED_TOTAL}[,}]"; then
  echo "OK: el total es ${EXPECTED_TOTAL}, como se esperaba."
else
  echo "ERROR: se esperaba HTTP 200 con total ${EXPECTED_TOTAL}." >&2
  exit 1
fi
