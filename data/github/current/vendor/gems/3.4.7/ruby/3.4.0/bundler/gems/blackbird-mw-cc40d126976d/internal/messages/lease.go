package messages

import (
	"sync/atomic"
	"time"
)

// A Lease allows blackbird-mw and blackbird to synchronize snapshot state,
// specifically to coordinate deletion (GC) of entries. Leases are Unix time
// since the epoch represented as int64s. A lease can only be extended (moved
// into the future) and a snapshot entry is only valid for modification if the
// lease time is ahead of Kakfa's LogAppendTime.
//
// See [ADR 35. Garbage Collection](https://github.com/github/blackbird/blob/main/docs/adr/0035-garbage-collection.md)
// for more details.
type Lease struct {
	expiresAt atomic.Int64
}

// Create a new lease which is valid for the next 2 hours.
func NewLease() *Lease {
	// NOTE: Kafka's LogAppendTime is UTC (not Pacific)
	return NewLeaseFromUnixMilli(time.Now().UTC().Add(2 * time.Hour).UnixMilli())
}

// Create a new lease from an int64 representing milliseconds since the Unix
// epoch.
func NewLeaseFromUnixMilli(t int64) *Lease {
	l := Lease{}
	l.expiresAt.Store(t)
	return &l
}

// Get when the lease expires as milliseconds since the Unix epoch.
func (l *Lease) ExpiresAt() int64 {
	return l.expiresAt.Load()
}

// Get when the lease expires as a time.Time.
func (l *Lease) ExpiresAtTime() time.Time {
	return time.UnixMilli(l.ExpiresAt())
}

// Returns true if the lease is expired as related to logAppendTime.
func (l *Lease) IsExpired(logAppend time.Time) bool {
	return logAppend.UnixMilli() > l.ExpiresAt()
}

// Set the lease expiration to a new value.
func (l *Lease) SetUnixMilli(new int64) {
	l.expiresAt.Store(new)
}
