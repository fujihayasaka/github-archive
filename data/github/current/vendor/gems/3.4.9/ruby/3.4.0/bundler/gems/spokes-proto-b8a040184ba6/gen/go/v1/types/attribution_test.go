package types

import (
	"testing"
	"time"

	"github.com/golang/protobuf/proto"
	"github.com/stretchr/testify/require"
)

const (
	name  = "Example Exampleson"
	email = "example@example.com"
)

func TestNewAttribution(t *testing.T) {
	now := time.Now()
	ts := NewTimestamp(now)

	a := NewAttribution(name, email, now)
	require.Equal(t, &Attribution{Name: name, Email: email, Date: ts}, a)
}

func TestAttributionMarshalling(t *testing.T) {
	now := time.Now()

	var tests = []struct {
		title   string
		attr    *Attribution
		isValid bool
	}{
		{
			"valid UTF-8",
			NewAttribution("Example Exampleson", "example@example.com", now),
			true,
		},
		{
			"invalid UTF-8",
			NewAttribution("Example\x80\x81\x82Exampleson", "example\x83@example.com", now),
			false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.title, func(t *testing.T) {
			_, err := proto.Marshal(tt.attr)
			if tt.isValid {
				require.NoErrorf(t, err, "received unexpected marshalling error")
			} else {
				require.Error(t, err, "did not receive expected marshalling error")
			}
		})
	}
}
