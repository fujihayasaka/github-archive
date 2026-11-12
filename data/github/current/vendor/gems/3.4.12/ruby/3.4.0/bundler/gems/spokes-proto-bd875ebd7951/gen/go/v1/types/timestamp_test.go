package types

import (
	"testing"
	"time"

	timestamppb "github.com/golang/protobuf/ptypes/timestamp"
	"github.com/stretchr/testify/require"
)

const (
	instant = "2021-03-01T13:31:03+01:00"
	seconds = 1614601863 // seconds since instant
	offset  = 3600       // an hour
)

func newTimestamp(seconds int64, offset int32) *Timestamp {
	return &Timestamp{
		Timestamp: &timestamppb.Timestamp{
			Seconds: seconds,
		},
		Offset: offset,
	}
}

func TestNewTimestamp(t *testing.T) {
	tt, err := time.Parse(time.RFC3339, instant)
	require.NoError(t, err)

	ts := NewTimestamp(tt)
	require.Equal(t, &Timestamp{Timestamp: &timestamppb.Timestamp{Seconds: seconds}, Offset: offset}, ts)
}

func TestTimestampValidateErrors(t *testing.T) {
	var tests = []struct {
		name      string
		timestamp *Timestamp
		err       string
	}{
		{"empty", &Timestamp{}, "twirp error invalid_argument: timestamp.timestamp is required"},
		{"below minimum timestamp", newTimestamp(minValidSeconds-1, 0), "twirp error invalid_argument: timestamp.timestamp is before 0001-01-01"},
		{"above maximum timestamp", newTimestamp(maxValidSeconds, 0), "twirp error invalid_argument: timestamp.timestamp is after 10000-01-01"},
		{"below minimum offset", newTimestamp(0, -daySeconds-1), "twirp error invalid_argument: timestamp.offset time zone offset has to be within a day"},
		{"above maximum offset", newTimestamp(0, daySeconds), "twirp error invalid_argument: timestamp.offset time zone offset has to be within a day"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.timestamp.Validate(), tt.err)
		})
	}
}

func TestTimestampValidate(t *testing.T) {
	var ts *Timestamp
	require.NoError(t, ts.Validate())

	tt, err := time.Parse(time.RFC3339, instant)
	require.NoError(t, err)

	ts = NewTimestamp(tt)
	require.NoError(t, ts.Validate())
}

func TestTimestampValidateGitErrors(t *testing.T) {
	var tests = []struct {
		name      string
		timestamp *Timestamp
		err       string
	}{
		{"empty", &Timestamp{}, "twirp error invalid_argument: timestamp.timestamp is required"},
		{"below minimum timestamp", newTimestamp(minGitSeconds-1, 0), "twirp error invalid_argument: timestamp.timestamp is before 1970-01-01 00:00:00"},
		{"above maximum timestamp", newTimestamp(maxGitSeconds+1, 0), "twirp error invalid_argument: timestamp.timestamp is after 2099-12-31 23:59:59"},
		{"invalid offset", newTimestamp(seconds, +1234), "twirp error invalid_argument: timestamp.offset must be divisible by 60"},
		{"below minimum offset", newTimestamp(0, -daySeconds-60), "twirp error invalid_argument: timestamp.offset time zone offset has to be within a day"},
		{"above maximum offset", newTimestamp(0, daySeconds), "twirp error invalid_argument: timestamp.offset time zone offset has to be within a day"},
		{"below minimum timestamp with offset", newTimestamp(minGitSeconds, -3600), "twirp error invalid_argument: timestamp.timestamp is before 1970-01-01 00:00:00 with offset"},
		{"above maximum timestamp with offset", newTimestamp(maxGitSeconds, +3600), "twirp error invalid_argument: timestamp.timestamp is after 2099-12-31 23:59:59 with offset"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.timestamp.ValidateGit(), tt.err)
		})
	}
}

func TestTimestampValidateGit(t *testing.T) {
	var ts *Timestamp
	require.NoError(t, ts.Validate())

	tt, err := time.Parse(time.RFC3339, instant)
	require.NoError(t, err)

	ts = NewTimestamp(tt)
	require.NoError(t, ts.ValidateGit())
}

func TestTimestampTime(t *testing.T) {
	tp, err := time.Parse(time.RFC3339, instant)
	require.NoError(t, err)

	ts := NewTimestamp(tp)
	require.NoError(t, ts.Validate())

	tt := ts.Time()
	require.Equal(t, instant, tt.Format(time.RFC3339))
}
