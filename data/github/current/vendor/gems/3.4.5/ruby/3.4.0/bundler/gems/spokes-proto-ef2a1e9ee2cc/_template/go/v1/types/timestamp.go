package types

import (
	"time"

	timestamppb "github.com/golang/protobuf/ptypes/timestamp"
	"github.com/twitchtv/twirp"
)

// The valid second constants are from Google's timestamp helpers
const (
	// This is time.Date(1, 1, 1, 0, 0, 0, 0, time.UTC).Unix().
	minValidSeconds = -62135596800
	// This is time.Date(10000, 1, 1, 0, 0, 0, 0, time.UTC).Unix().
	maxValidSeconds = 253402300800

	// Timestamps used for Git (e.g. in attributions) cannot predate 1970-01-01
	// 00:00:00, both with and without the offset.
	minGitSeconds = 0
	// Timestamps used for Git (e.g. in attributions) cannot be larger than
	// 2099-12-31 23:59:59, both with and without the offset.
	maxGitSeconds = 4102444799

	// Number of seconds in a day, used for min/max in offset
	daySeconds = 24 * 60 * 60
)

func NewTimestamp(t time.Time) *Timestamp {
	_, offset := t.Zone()

	return &Timestamp{
		Timestamp: &timestamppb.Timestamp{
			Seconds: t.Unix(),
		},
		Offset: int32(offset),
	}
}

func (t *Timestamp) Validate() error {
	if t == nil {
		return nil
	}

	if t.GetTimestamp() == nil {
		return twirp.RequiredArgumentError("timestamp.timestamp")
	}

	if t.Timestamp.Seconds < minValidSeconds {
		return twirp.InvalidArgumentError("timestamp.timestamp", "is before 0001-01-01")
	}

	if t.Timestamp.Seconds >= maxValidSeconds {
		return twirp.InvalidArgumentError("timestamp.timestamp", "is after 10000-01-01")
	}

	if t.Offset < -daySeconds || t.Offset >= daySeconds {
		return twirp.InvalidArgumentError("timestamp.offset", "time zone offset has to be within a day")
	}

	return nil
}

func (t *Timestamp) ValidateGit() error {
	if t == nil {
		return nil
	}

	if t.GetTimestamp() == nil {
		return twirp.RequiredArgumentError("timestamp.timestamp")
	}

	if t.Timestamp.Seconds < minGitSeconds {
		return twirp.InvalidArgumentError("timestamp.timestamp", "is before 1970-01-01 00:00:00")
	}

	if t.Timestamp.Seconds > maxGitSeconds {
		return twirp.InvalidArgumentError("timestamp.timestamp", "is after 2099-12-31 23:59:59")
	}

	if t.Offset%60 != 0 {
		return twirp.InvalidArgumentError("timestamp.offset", "must be divisible by 60")
	}

	if t.Offset < -daySeconds || t.Offset >= daySeconds {
		return twirp.InvalidArgumentError("timestamp.offset", "time zone offset has to be within a day")
	}

	if t.Timestamp.Seconds+int64(t.Offset) < minGitSeconds {
		return twirp.InvalidArgumentError("timestamp.timestamp", "is before 1970-01-01 00:00:00 with offset")
	}

	if t.Timestamp.Seconds+int64(t.Offset) > maxGitSeconds {
		return twirp.InvalidArgumentError("timestamp.timestamp", "is after 2099-12-31 23:59:59 with offset")
	}

	return nil
}

func (t *Timestamp) Time() time.Time {
	if t == nil {
		return time.Unix(0, 0).UTC()
	}

	loc := time.FixedZone("", int(t.Offset))
	return time.Unix(t.Timestamp.Seconds, 0).In(loc)
}
