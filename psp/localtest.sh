#!/usr/bin/env bash

command -v curl >/dev/null 2>&1 || { echo 'You need curl to use this.'; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'You need jq to use this.'; exit 1; }

# Just a Bash trick to check if there's something on host/port:
( </dev/tcp/localhost/8001 ) 2>/dev/null; psp1=$?
( </dev/tcp/localhost/8002 ) 2>/dev/null; psp2=$?

if [[ $psp1 -ne 0 && $psp2 -ne 0 ]]; then
    echo 'ERROR: no PSP is listening.' >&2
    echo '(probably you just forgot to start them)' >&2
    exit 1
elif [[ $psp1 -ne 0 ]]; then
    echo 'WARNING: default PSP is not listening on port 8001.' >&2
elif [[ $psp2 -ne 0 ]]; then
    echo 'WARNING: fallback PSP is not listening on port 8002.' >&2
fi

BASE_URL="http://localhost:8001"  # requests hit payment-processor-1 by default


usage() {
    cat <<EOF 1>&2
Usage: $0 [-F] (-p | -P | -x | -s | -h | -d <ms> | -f <true|false>)
Note: option -F, if present, must precede the action.

    -F              Target the fallback PSP
    -p              Make a payment
    -P              Make a payment and retrieve its info via /payments/<UUID>
    -x              Truncate the payments table
    -s              Print summary
    -h              Call GET /payments/service-health
    -d <ms>         Add a minimum latency of <ms> milliseconds
    -f <true|false> Set failure mode
EOF
}


set_delay() {
    curl -s "${BASE_URL}/admin/configurations/delay" \
        -D '%' \
        -X PUT \
        -H 'Content-Type:application/json' \
        -H 'X-Rinha-Token:123' \
        -d "{\"delay\":${1}}" \
    | jq --indent 4
}


set_failure() {
    curl -s "${BASE_URL}/admin/configurations/failure" \
        -D '%' \
        -X PUT \
        -H 'Content-Type:application/json' \
        -H 'X-Rinha-Token:123' \
        -d "{\"failure\":${1}}" \
    | jq --indent 4
}


purge() {
    curl -s "${BASE_URL}/admin/purge-payments" \
        -D '%' \
        -X POST \
        -H 'X-Rinha-Token:123' \
    | jq --indent 4
}


pay() {
    json=$(
        jq -ncM \
            --arg id "$(uuidgen)" \
            --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')" \
            '{correlationId:$id,amount:19.9,requestedAt:$ts}'
    )

    curl -s "${BASE_URL}/payments" \
        -D '%' \
        -X POST \
        -H 'Content-Type:application/json' \
        -d "$json" \
    | jq --indent 4
}


pay_and_fetch() {
    uuid="$(uuidgen)"
    json=$(
        jq -ncM \
            --arg id "$uuid" \
            --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')" \
            '{correlationId:$id,amount:19.9,requestedAt:$ts}'
    )

    pay=$(
        curl -si --fail-with-body "${BASE_URL}/payments" \
            -X POST \
            -H 'Content-Type:application/json' \
            -d "$json"
    )

    if [[ $? -eq 0 ]]; then
        curl -s "${BASE_URL}/payments/${uuid}" \
            -D '%' \
            -X GET \
        | jq --indent 4
    else
        echo "$pay"
    fi
}


healthcheck() {
    curl -s "${BASE_URL}/payments/service-health" \
        -D '%' \
        -X GET \
    | jq --indent 4
}


summary() {
    curl -s "${BASE_URL}/admin/payments-summary" \
        -D '%' \
        -X GET \
        -H 'X-Rinha-Token:123' \
    | jq --indent 4
}


while getopts ':FpPd:f:xsh' opt; do
    case $opt in
        F)
            BASE_URL="http://localhost:8002"
            ;;
        p)
            pay
            exit
            ;;
        P)
            pay_and_fetch
            exit
            ;;
        d)
            set_delay "$OPTARG"
            exit
            ;;
        f)
            set_failure "$OPTARG"
            exit
            ;;
        x)
            purge
            exit
            ;;
        s)
            summary
            exit
            ;;
        h)
            healthcheck
            exit
            ;;
        :)
            echo -e "ERROR: option -${OPTARG} requires an argument.\n" >&2
            usage
            exit 1
            ;;
        ?)
            echo -e "ERROR: option -${OPTARG} doesn't exist.\n" >&2
            usage
            exit 1
            ;;
    esac
done


echo -e 'ERROR: you must provide at least 1 action.\n' >&2
usage
exit 1
