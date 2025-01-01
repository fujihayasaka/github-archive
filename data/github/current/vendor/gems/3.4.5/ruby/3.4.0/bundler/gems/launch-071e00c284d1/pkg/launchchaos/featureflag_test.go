package launchchaos

import (
	"context"
	"fmt"
	"math/rand"
	"testing"
)

func Test_featureFlagParticipator_Participate(t *testing.T) {
	tests := []struct {
		participation float32
	}{
		{
			participation: 0.1,
		},
		{
			participation: 0.2,
		},
		{
			participation: 0.3,
		},
		{
			participation: 0.4,
		},
		{
			participation: 0.5,
		},
		{
			participation: 0.6,
		},
		{
			participation: 0.7,
		},
		{
			participation: 0.8,
		},
		{
			participation: 0.9,
		},
		{
			participation: 1.0,
		},
	}
	for _, tt := range tests {
		t.Run(fmt.Sprintf("%f", tt.participation), func(t *testing.T) {
			r := rand.New(rand.NewSource(defaultRandSeed))
			rf := r.Float32
			ffp := &featureFlagParticipator{
				featureFlag:   "test",
				checkF:        func(ctx context.Context, featureFlag string) bool { return true },
				participation: tt.participation,
				randFunc:      rf,
			}
			counter := 0
			for i := 0; i < 100; i++ {
				if ffp.Participate(context.TODO()) {
					counter++
				}
			}

			min := int(tt.participation*100 - ((tt.participation * 100) * .20))
			max := int(tt.participation*100 + ((tt.participation * 100) * .20))
			if !(counter >= min && counter <= max) {
				t.Errorf("out of tolerable range, got %d, expected between [%d,%d]", counter, min, max)
			}
		})
	}
}
