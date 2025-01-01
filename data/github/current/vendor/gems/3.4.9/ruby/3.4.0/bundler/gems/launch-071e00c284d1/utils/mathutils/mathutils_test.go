package mathutils

import (
	"math/rand"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestRandomInt64(t *testing.T) {

	r := rand.New(rand.NewSource(42))
	for i := 0; i < 100; i++ {
		assert.Equal(t, int64(0), RandomInt64(r, 0, 1))
	}

	low := int64(999999)
	high := int64(-1)
	for i := 0; i < 100; i++ {
		n := RandomInt64(r, 0, 2)
		low = min(n, low)
		high = max(n, high)
	}
	assert.Equal(t, int64(0), low)
	assert.Equal(t, int64(1), high)

	low = int64(999999)
	high = int64(-1)
	for i := 0; i < 100; i++ {
		n := RandomInt64(r, 1, 11)
		low = min(n, low)
		high = max(n, high)
	}
	assert.Equal(t, int64(1), low)
	assert.Equal(t, int64(10), high)
}

func TestRandomInt64_Distribution(t *testing.T) {

	r := rand.New(rand.NewSource(9))
	distribution := [10]int{}
	iterations := 15000
	floor := int64(100)
	for i := 0; i < iterations; i++ {
		n := RandomInt64(r, floor, floor+10)
		distribution[n-floor]++
	}

	// Ensure that the distribution is roughly uniform
	perfect := float64(iterations / len(distribution))
	tolerance := perfect / 20.0 // 5% tolerance
	for _, n := range distribution {
		assert.InDelta(t, perfect, n, tolerance)
	}
}

func TestRandomFloat64_Contrived(t *testing.T) {

	var r RandProvider = rand.New(rand.NewSource(42))
	for i := 0; i < 100; i++ {
		assert.Equal(t, 0.0, RandomFloat64(r, 0, 0))
	}

	// Define a "fake" RandProvider that always returns 0.0 (corresponding to the floor of any interval)
	r = newConstantGenerator(0, 0.0)
	assert.Equal(t, 0.0, RandomFloat64(r, 0, 0))
	assert.Equal(t, 0.0, RandomFloat64(r, 0, 1))
	assert.Equal(t, 0.0, RandomFloat64(r, 0, 10))
	assert.Equal(t, 0.0, RandomFloat64(r, 0, 100))
	for i := -3.0; i <= 3.0; i += 0.25 {
		assert.Equal(t, i, RandomFloat64(r, i, 10))
	}

	// Define a "fake" RandProvider that always returns 0.5 (corresponding to the midpoint of any interval)
	r = newConstantGenerator(0, 0.5)
	assert.Equal(t, 0.0, RandomFloat64(r, 0, 0))

	for high := 1.0; high <= 100000; high *= 10 {
		for low := 0.0; low <= 10; low++ {
			if low < high {
				n := RandomFloat64(r, low, high)
				assert.Equal(t, (low+high)/2.0, n, "low: %f, high: %f", low, high)
			}
		}
	}

	// Define a "fake" RandProvider that always returns 0.999999999 (corresponding to the ceiling of any interval)
	seed := 0.999999
	r = newConstantGenerator(0, seed)
	assert.Equal(t, 0.0, RandomFloat64(r, 0, 0))

	for high := 1.0; high <= 100000; high *= 10 {
		for low := 1.0; low <= 10; low++ {
			if low < high {
				n := RandomFloat64(r, low, high)
				assert.Less(t, n, high)
				tolerance := (high) * (1.0 - seed) //  1e-6 (0.000001), 1e-5, 1e-4, etc.
				assert.InDelta(t, seed*high, n, tolerance, "low: %f, high: %f", low, high)
			}
		}
	}
}

func TestRandomFloat64_Distribution(t *testing.T) {

	r := rand.New(rand.NewSource(9))
	distribution := [100]int{}
	iterations := 75000
	floor := 100.0
	ceiling := 2.0 * floor
	bucketWidth := (ceiling - floor) / float64(len(distribution))
	for i := 0; i < iterations; i++ {
		n := RandomFloat64(r, floor, ceiling)
		bucketIndex := int((n - floor) / bucketWidth)
		distribution[bucketIndex]++
	}

	// Ensure that the distribution is roughly uniform
	perfect := float64(iterations / len(distribution))
	tolerance := perfect / 10 // 10% tolerance
	for _, n := range distribution {
		assert.InDelta(t, perfect, n, tolerance)
	}
}

type constantGenerator struct {
	i int64
	f float64
}

func (cg *constantGenerator) Int63n(n int64) int64 {
	return min(cg.i, n)
}

func (cg *constantGenerator) Float64() float64 {
	return cg.f
}

func newConstantGenerator(constantInt int64, constantFloat float64) RandProvider {
	return &constantGenerator{i: constantInt, f: constantFloat}
}
