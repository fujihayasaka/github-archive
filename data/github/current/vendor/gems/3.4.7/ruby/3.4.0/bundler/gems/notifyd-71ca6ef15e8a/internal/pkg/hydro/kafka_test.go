package hydro

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestConfig_Brokers(t *testing.T) {
	r := require.New(t)
	tests := []struct {
		name    string
		brokers string
		want    []string
	}{
		{
			name:    "empty",
			brokers: "",
			want:    []string{""},
		},
		{
			name:    "one",
			brokers: "kafka://localhost:9092",
			want:    []string{"kafka://localhost:9092"},
		},
		{
			name:    "two",
			brokers: "kafka://localhost:9092,kafka://localhost:9093",
			want:    []string{"kafka://localhost:9092", "kafka://localhost:9093"},
		},
		{
			name:    "two with space",
			brokers: "kafka://localhost:9092, kafka://localhost:9093",
			want:    []string{"kafka://localhost:9092", "kafka://localhost:9093"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := &Config{
				KafkaBrokers: tt.brokers,
			}
			got := c.Brokers()
			r.Equal(tt.want, got)
		})
	}
}
