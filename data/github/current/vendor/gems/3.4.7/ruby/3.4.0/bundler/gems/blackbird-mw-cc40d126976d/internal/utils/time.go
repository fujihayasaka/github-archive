package utils

import "time"

// TimeFromServingTs takes a blackbird shard serving timestamp (milliseconds since the
// Unix epoch) and returns a time.Time in UTC.
func TimeFromServingTs(servingTs int64) time.Time {
	return time.UnixMilli(servingTs)
}
