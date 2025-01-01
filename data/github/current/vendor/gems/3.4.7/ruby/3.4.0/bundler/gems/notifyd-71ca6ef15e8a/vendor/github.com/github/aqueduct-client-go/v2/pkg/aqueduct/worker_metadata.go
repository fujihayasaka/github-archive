package aqueduct

import (
	"fmt"
	"os"

	gonanoid "github.com/matoous/go-nanoid/v2"
)

type WorkerMetadata struct {
	Hostname string
	PID      int
	ID       string
	Pool     string
}

func NewWorkerMetadata(pool string) WorkerMetadata {
	host, err := os.Hostname()
	if err != nil {
		host = "N/A"
	}

	pid := os.Getpid()

	// The aqueduct-gateway relies on a hash of the clientID and the current minute to determine
	// the routing backend probability of a request. The clientID should be unique per worker
	// so worker allocation matches the aqueduct-gateway's Receive backend weights.
	// i.e. If only 2% of receives should go to the secondary, 10 workers share the same clientID,
	// and that clientID would pick the secondary - all 10 workers would hit the secondary.
	entropy, _ := gonanoid.Generate(nanoIDAlphabet, defaultIDEntropyLength)
	workerID := fmt.Sprintf("%s:%d:%s", host, pid, entropy)

	return WorkerMetadata{
		Hostname: host,
		PID:      os.Getpid(),
		ID:       workerID,
		Pool:     pool,
	}
}
