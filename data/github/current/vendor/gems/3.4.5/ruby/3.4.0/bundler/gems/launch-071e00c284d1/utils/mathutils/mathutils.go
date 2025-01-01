package mathutils

import (
	"math/rand" // REVIEW:  consider also supporting math/rand/v2
	"sync"
	"time"
)

// Btoi converts a bool to an int, returning 1 for true and 0 for false.
func Btoi(b bool) int {
	if b {
		return 1
	}
	return 0
}

// RandProvider is an interface extruded from math/rand::Rand that encapsulates the most commonly-used Rand methods, Int63n and Float64.
// (Note that math/rand::Rand satisifies this interface.)
type RandProvider interface {
	// Int63n returns, as an int64, a non-negative pseudo-random number in the half-open interval [0,n).
	Int63n(n int64) int64

	// Float64 returns, as a float64, a pseudo-random number in the half-open interval [0.0,1.0).
	Float64() float64
}

// Uses the provided RandProvider to generate a random float64 in the half-open interval [min, max).
func RandomFloat64(r RandProvider, min, max float64) float64 {
	return min + r.Float64()*(max-min)
}

// Uses the provided RandProvider to generate a random int64 in the half-open interval [min, max).
func RandomInt64(r RandProvider, min, max int64) int64 {
	return min + r.Int63n(max-min)
}

// Synchronizes access to a RandProvider using an internal mutex.
type SynchronizedRandProvider struct {
	provider RandProvider
	mutex    sync.Mutex
}

func NewSynchronizedRandProviderFromClock() *SynchronizedRandProvider {
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	return NewSynchronizedRandProvider(r)
}

func NewSynchronizedRandProvider(provider RandProvider) *SynchronizedRandProvider {
	return &SynchronizedRandProvider{provider, sync.Mutex{}}
}

func (r *SynchronizedRandProvider) Int63n(n int64) int64 {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	return r.provider.Int63n(n)
}

func (r *SynchronizedRandProvider) Float64() float64 {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	return r.provider.Float64()
}
