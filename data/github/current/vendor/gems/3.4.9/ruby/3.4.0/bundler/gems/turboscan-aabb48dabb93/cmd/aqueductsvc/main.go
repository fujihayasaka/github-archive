// aqueductsvc is responsible for executing Aqueduct workers.
//
// To manually send a job to be processed do:
//
//   export AQUEDUCT_ADDR=http://localhost:18081
//   PAYLOAD=$(echo '{"Message": "potato"}' | base64)
//   curl --header "Content-Type:application/json" \
//      --data '{"app": "turboscan-dev", "queue":"turboscan-echo", "payload":"'$PAYLOAD'"}' \
//     $AQUEDUCT_ADDR/twirp/aqueduct.api.v1.JobQueueService/Send
//
// This will encode a job with a payload "potato" on the turboscan-echo queue.
// The turboscan-echo queue is a special queue for testing, the other queue we use is "default".
// More queues can be added to define various priorities and processing strategies.
//

package main

import (
	"os"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/cmd/aqueductsvc/root"
)

func main() {
	if err := root.AqueductCmd.Execute(); err != nil {
		log.WithError(err).Error("failed to run aqueductsvc")
		os.Exit(1)
	}
}
