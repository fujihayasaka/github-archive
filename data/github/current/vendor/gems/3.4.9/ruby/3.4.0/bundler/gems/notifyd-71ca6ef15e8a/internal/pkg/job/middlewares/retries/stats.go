package retries

import (
	"fmt"

	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/job/middlewares/retries/retriables"
)

type statsKey string

const (
	// statsProcessed is used to report the state of a message that has been retried. We only report
	// when the message has finally succeeded or failed.
	statsProcessed statsKey = "processed"
	// statsEnqueued is used to report when a message is enqueued for redelivery.
	statsEnqueued statsKey = "enqueued"
)

type statsStatus string

const (
	statsSuccess statsStatus = "success"
	statsFailed  statsStatus = "failed"
)

// statsCount reports information about the retry process so that we can know what has happened with
// retried messages and whether they have succeeded or not after retries.
func statsCount(statter stats.Client, msg retriables.Message, key statsKey, status statsStatus) {
	statsKey := fmt.Sprintf("retries.%s.count", key)
	tags := stats.Tags{"msg": msg.GetName(), "status": string(status)}
	statter.Counter(statsKey, tags, 1)
}
