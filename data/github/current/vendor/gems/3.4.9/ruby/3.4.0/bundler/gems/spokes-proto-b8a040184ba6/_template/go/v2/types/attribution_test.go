package types

import (
	"testing"
	"time"

	"github.com/golang/protobuf/proto"
	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

var (
	name           = []byte("Example Exampleson")
	email          = []byte("example@example.com")
	invalidGitDate = "1900-01-01T12:34:56+00:00"
)

func TestNewAttribution(t *testing.T) {
	now := time.Now()
	ts := types.NewTimestamp(now)

	a := NewAttribution(name, email, now)
	require.Equal(t, &Attribution{Name: name, Email: email, Date: ts}, a)
}

func TestAttributionMarshalling(t *testing.T) {
	now := time.Now()

	var tests = []struct {
		title string
		attr  *Attribution
	}{
		{
			"valid UTF-8",
			NewAttribution([]byte("Example Exampleson"), []byte("example@example.com"), now),
		},
		{
			"invalid UTF-8",
			NewAttribution([]byte("Example\x80\x81\x82Exampleson"), []byte("example\x83@example.com"), now),
		},
	}

	for _, tt := range tests {
		t.Run(tt.title, func(t *testing.T) {
			_, err := proto.Marshal(tt.attr)
			require.NoErrorf(t, err, "received unexpected marshalling error")
		})
	}
}

func TestAttributionValidateErrors(t *testing.T) {
	now := time.Now()
	invalidDate, err := time.Parse(time.RFC3339, invalidGitDate)
	require.NoError(t, err)

	var tests = []struct {
		name        string
		attribution *Attribution
		err         string
	}{
		{"empty", &Attribution{}, "twirp error invalid_argument: attribution.name is required"},
		{"empty name", NewAttribution([]byte(""), email, now), "twirp error invalid_argument: attribution.name is required"},
		{"crud name", NewAttribution([]byte("<:>"), email, now), "twirp error invalid_argument: attribution.name consists only of disallowed characters"},
		{"empty email", NewAttribution(name, []byte(""), now), "twirp error invalid_argument: attribution.email is required"},
		{"crud email", NewAttribution(name, []byte("\n;"), now), "twirp error invalid_argument: attribution.email consists only of disallowed characters"},
		{"nil timestamp", &Attribution{Name: name, Email: email, Date: nil}, "twirp error invalid_argument: attribution.date is required"},
		{"invalid Git timestamp", NewAttribution(name, email, invalidDate), "twirp error invalid_argument: timestamp.timestamp is before 1970-01-01 00:00:00"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.attribution.Validate(), tt.err)
		})
	}
}

func TestAttributionValidate(t *testing.T) {
	now := time.Now()

	var tests = []struct {
		name        string
		attribution *Attribution
	}{
		{"nil", nil},
		{"normal", NewAttribution(name, email, now)},
		{"name with crud", NewAttribution([]byte(",Some Author A;"), email, now)},
		{"name with diallowed character", NewAttribution([]byte("Some <Author>"), email, now)},
		{"email with crud", NewAttribution(name, []byte("\"my.email@example.com\""), now)},
		{"name with diallowed character", NewAttribution(name, []byte("my.email@example.com\nanother.email@example.com"), now)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.NoError(t, tt.attribution.Validate())
		})
	}
}
