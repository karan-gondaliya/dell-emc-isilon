#!/bin/bash

# Fill in the variables below before running.

set -euo pipefail


ISILON_IP="<ISILON_IP>"
ISILON_PORT="<ISILON_PORT>"
USERNAME="<USERNAME>"
PASSWORD="<PASSWORD>"

# Platform API versions to query for NFS exports
NFS_EXPORT_VERSIONS=(14 19 24)

# Platform API versions to query for NFS workload stats
WORKLOAD_VERSIONS=(14 10 24)

BASE_URI="https://${ISILON_IP}:${ISILON_PORT}"
AUTH_HEADERS_FILE=$(mktemp)

cleanup() {
    rm -f "${AUTH_HEADERS_FILE}"
}
trap cleanup EXIT

if [[ -z "${ISILON_IP}" || -z "${ISILON_PORT}" || -z "${USERNAME}" || -z "${PASSWORD}" ]]; then
    echo "Error: Please set ISILON_IP, ISILON_PORT, USERNAME and PASSWORD at the top of the script." >&2
    exit 1
fi


echo "Authenticating to ${BASE_URI} ..."

curl -sk -i -X POST "${BASE_URI}/session/1/session" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"${USERNAME}\", \"password\": \"${PASSWORD}\", \"services\": [\"platform\", \"namespace\"]}" \
    -D "${AUTH_HEADERS_FILE}" -o /dev/null

if ! grep -qi "^HTTP/.* 201" "${AUTH_HEADERS_FILE}"; then
    echo "Error: Authentication failed. Response headers:" >&2
    cat "${AUTH_HEADERS_FILE}" >&2
    exit 1
fi

ISISESSID=$(grep -o 'isisessid=[^;]*' "${AUTH_HEADERS_FILE}" | head -1 | cut -d= -f2-)
ISICSRF=$(grep -o 'isicsrf=[^;]*' "${AUTH_HEADERS_FILE}" | head -1 | cut -d= -f2)

if [[ -z "${ISISESSID}" || -z "${ISICSRF}" ]]; then
    echo "Error: Could not extract session cookie / CSRF token from auth response." >&2
    exit 1
fi

echo "Authentication successful."

fetch_and_store() {
    VERSION="$1"
    API_PATH="$2"
    URL="${BASE_URI}/platform/${VERSION}${API_PATH}"
    echo "Fetching ${API_PATH} from platform/${VERSION} ..."

    echo "===================================================================="
    echo "Platform version : ${VERSION}"
    echo "Endpoint         : ${URL}"
    echo "===================================================================="

    RESPONSE=$(curl -sk -X GET "${URL}" \
        -H "X-CSRF-Token: ${ISICSRF}" \
        -H "Cookie: isisessid=${ISISESSID}" \
        -H "Referer: ${BASE_URI}")

    if command -v jq >/dev/null 2>&1 && echo "${RESPONSE}" | jq empty >/dev/null 2>&1; then
        echo "${RESPONSE}" | jq '.'
    else
        echo "${RESPONSE}"
    fi

    echo ""
}

for VERSION in "${NFS_EXPORT_VERSIONS[@]}"; do
    fetch_and_store "${VERSION}" "/protocols/nfs/exports"
done

for VERSION in "${WORKLOAD_VERSIONS[@]}"; do
    fetch_and_store "${VERSION}" "/statistics/summary/workload"
done

echo ""
echo "Done."
