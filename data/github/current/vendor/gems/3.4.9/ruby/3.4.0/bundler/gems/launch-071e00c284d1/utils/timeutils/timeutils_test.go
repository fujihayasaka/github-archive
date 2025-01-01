package timeutils

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestScaleDuration(t *testing.T) {
	for i := -10; i < 10; i++ {
		expected := time.Duration(i) * time.Second
		assert.Equal(t, expected, ScaleDuration(i, time.Second))
		assert.Equal(t, expected, ScaleDuration(int64(i), time.Second))
		assert.Equal(t, expected, ScaleDuration(float64(i), time.Second))
	}

	for f := -10.0; f < 10.0; f += 0.25 {
		expected := time.Duration(f * float64(time.Second))
		assert.Equal(t, expected, ScaleDuration(f, time.Second))
	}
}
