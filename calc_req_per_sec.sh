#!/usr/bin/env bash
set -euo pipefail

# Calculate the request count per second through the information from NGINX stub_status and send it to AWS Cloudwatch.
# requests_per_second = (requests - previous_requests) / interval

# Required commands
curl_cmd=$(command -v curl)
awk_cmd=$(command -v awk)
flock_cmd=$(command -v flock)
jq_cmd=$(command -v jq)

# Define the path for the runtime
readonly TIMESTAMP=$(date +%s)
readonly SCRIPT_NAME=$(basename "$0" | sed 's/\.sh$//g')
readonly REQUIRED_DIR="${TMPDIR:-/tmp}/sre/script/${SCRIPT_NAME}"
readonly RESULT_DIR="${REQUIRED_DIR}/result"
readonly TMP_DIR="${REQUIRED_DIR}/tmp"
readonly LOG_DIR="${REQUIRED_DIR}/logs"
readonly LOCKFILE="${TMP_DIR}/${SCRIPT_NAME}.lock"
readonly NGINX_PREVIOUS_STATUS="${RESULT_DIR}/${SCRIPT_NAME}.dat"
readonly LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
readonly NGINX_URI="http://127.0.0.1/nginx_status"

# Error Handler
err_catch() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" 2>&1 >>${LOG_FILE}
}

# Create the required folder for the runtime
if ! mkdir -p ${TMP_DIR} ${RESULT_DIR} ${LOG_DIR}; then
  err_catch "Unable to create or write to the required directory."
  exit 1
fi

# Script runtime handler
# Use flock to create a lock file
lock_proc() {
  touch ${LOCKFILE} && exec {FD}<>$LOCKFILE
}
# unlock process
unlock_proc() {
  flock -u -o $FD && rm -f ${LOCKFILE}
}

check_runtime_requirements() {
  # Check if the REQUIRED_DIR exists and is writable
  if [[ -d "${TMP_DIR}" && -w "${TMP_DIR}" ]] &&
    [[ -d "${RESULT_DIR}" && -w "${RESULT_DIR}" ]] &&
    [[ -d "${LOG_DIR}" && -w "${LOG_DIR}" ]]; then
    lock_proc
    if ! flock -xn -o $FD; then
      err_catch "Another process of $(basename $0) is probably running."
      exit 1
    fi
  else
    err_catch "Unable to write to either ${TMP_DIR} or ${RESULT_DIR} or ${LOG_DIR}"
    exit 1
  fi

}

previous_nginx_status() {
  if [[ ! -f ${NGINX_PREVIOUS_STATUS} ]]; then
    if ! touch ${NGINX_PREVIOUS_STATUS}; then
      err_catch "Unable to create or write to ${NGINX_PREVIOUS_STATUS}"
      exit 1
    fi
  else
    export previous_result_time=$(awk '{print $1}' ${NGINX_PREVIOUS_STATUS})
    export previous_result_requests=$(awk '{print $2}' ${NGINX_PREVIOUS_STATUS})
  fi
}

get_nginx_status() {
  if [ "$($curl_cmd -sI "${NGINX_URI}" | head -1 | awk '{print $2}')" == "200" ]; then
    eval $($curl_cmd -s "${NGINX_URI}" |
      $awk_cmd '/accepts handled requests/ \
      { getline; print "accepts=" $1 " handled=" $2 " requests=" $3 }')
    export accepts=$accepts handled=$handled requests=$requests
  else
    err_catch "Nginx status page not found"
    exit 1
  fi
}

put_metric_to_cloudwatch() {
  if [[ -f "/etc/profile.d/ebenv.sh" ]]; then
    source "/etc/profile.d/ebenv.sh"
    AWS_DEFAULT_REGION=$(${curl_cmd} -s http://169.254.169.254/latest/dynamic/instance-identity/document | ${jq_cmd} -r .region)
    INSTANCE_ID_URL="http://169.254.169.254/latest/meta-data/instance-id"
    INSTANCE_ID=$(${curl_cmd} -s ${INSTANCE_ID_URL})
    HOSTNAME="$HOSTNAME"
    NAMESPACE="ElasticBeanstalk/$EB_ENV_NAME"
    METRIC_TIMESTAMP=$(date -u -d @${TIMESTAMP} '+%Y-%m-%dT%H:%M:%SZ')
    STORAGE_RESOLUTION="1"
  fi

  PUT_METRIC_CMD="/bin/env \
    AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
    aws cloudwatch put-metric-data \
    --region ${AWS_DEFAULT_REGION} \
    --dimensions EnvironmentName=${NAMESPACE} \
    --namespace ${NAMESPACE} \
    --storage-resolution ${STORAGE_RESOLUTION} \
    --timestamp ${TIMESTAMP}"

  # put RequestCountPerSec metric data
  ${PUT_METRIC_CMD} --metric-name RequestCountPerSec --unit Count --storage-resolution 1 --value $1
}

main() {
  if [[ -z ${previous_result_time} ]]; then
    previous_result_time="0"
  fi
  if [[ -z ${previous_result_requests} ]]; then
    previous_result_requests="0"
  fi
  interval_seconds=$((${TIMESTAMP} - ${previous_result_time}))
  request_count_per_secound=$(((${requests} - ${previous_result_requests}) / ${interval_seconds}))

  put_metric_to_cloudwatch ${request_count_per_secound}
  echo -n "${TIMESTAMP} ${requests}" >${NGINX_PREVIOUS_STATUS}
}

check_runtime_requirements
get_nginx_status
previous_nginx_status
main
unlock_proc
