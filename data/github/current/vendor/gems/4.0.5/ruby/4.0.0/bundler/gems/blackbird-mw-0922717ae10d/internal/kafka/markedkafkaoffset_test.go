package kafka

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_NewMarkedKafkaOffsetFromRaw(t *testing.T) {
	var tests = []struct {
		raw   int64
		kafka int64
	}{
		{
			raw:   0,
			kafka: 0,
		},
		{
			raw:   1,
			kafka: 1,
		},
		{
			raw:   0 | markedOffsetMask,
			kafka: 0,
		},
		{
			raw:   1 | markedOffsetMask,
			kafka: 1,
		},
	}

	for _, test := range tests {
		t.Run(fmt.Sprintf("raw offset=%d kafka offset=%d", test.raw, test.kafka), func(t *testing.T) {
			mark := test.kafka != test.raw
			mko := MarkedKafkaOffset{test.kafka, mark}
			markedOffset := NewMarkedKafkaOffsetFromRaw(test.raw)
			require.Equal(t, mko, markedOffset, "expected %+v got %+v", mko, markedOffset)
			require.Equal(t, test.kafka, markedOffset.Get())
			require.Equal(t, test.raw, markedOffset.Raw())
		})
	}
}

// The MarkedKafkaOffset struct can represent a negative offset, but that's illegal.
func Test_NegativeOffsetAsRawPanics(t *testing.T) {
	mko := MarkedKafkaOffset{-1, true}
	require.Panics(t, func() {
		mko.Raw()
	})
}
