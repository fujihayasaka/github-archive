certs_dir=`dirname ${BASH_SOURCE[0]:-${(%):-%x}}`/../../certs
export SPOKESD_CLIENT_CERT="`cat $certs_dir/test-client.crt`"
export SPOKESD_CLIENT_KEY="`cat $certs_dir/test-client.key`"
export SPOKESD_CA_FILE="$certs_dir/chain.pem"

export HMAC_KEY="spokes-proto-hmac-key"
