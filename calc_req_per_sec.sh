#!/usr/bin/env bash
set -euo pipefail
#
# Calculate the request count per second through the information from NGINX stub_status and send it to AWS Cloudwatch.
# requests_per_second = (handled_requests - previous_handled_requests) / interval

# Required commands
curl_cmd=$(command -v curl)
awk_cmd=$(command -v awk)

# Error Handler
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

# if ! do_something; then
#     err "Unable to do_something"
#     exit 1
# fi

# Define the path for the runtime
readonly RUNTIME_DIR="./sre"
readonly RESULT_DIR="${RUNTIME_DIR}/result"
readonly TMP_DIR="${RUNTIME_DIR}/tmp"
readonly SCRIPT_NAME=$(basename "$0" | sed 's/\.sh$//g')
readonly LOCK_FILE="./tmp/${SCRIPT_NAME}.lock"
readonly NGINX_LATEST_STATUS="./tmp/${SCRIPT_NAME}.dat"

# Create the required folder for the runtime
if [[ -d ${RUNTIME_DIR} && -w ${RUNTIME_DIR} ]]; then
  mkdir -p ${RUNTIME_DIR}/{tmp,result}
else
  sudo rm -rf ${RUNTIME_DIR} && mkdir -p ${RUNTIME_DIR}/{tmp,result} && chmod 0755 $_
fi

# get_nginx_status() {
#   eval $($curl_cmd -s "http://18.208.160.119/nginx_status" |
#     $awk_cmd '/accepts handled requests/ \
#       { getline; print "accepts=" $1 " handled=" $2 " requests=" $3 }')
#   export accepts=$accepts handled=$handled requests=$requests
# }

# get_nginx_status
echo $RUNTIME_DIR
echo $RESULT_DIR
echo $TMP_DIR
echo $SCRIPT_NAME
echo $LOCK_FILE
echo $NGINX_LATEST_STATUS
