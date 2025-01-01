package common

import (
	"context"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/sony/gobreaker"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestWithCircuitBreakerHappyPath(t *testing.T) {
	cb := gobreaker.NewCircuitBreaker(gobreaker.Settings{
		Name:        "test_circuit_breaker",
		MaxRequests: 1,
		Interval:    5 * time.Millisecond,
		Timeout:     1 * time.Millisecond,
		ReadyToTrip: func(_ gobreaker.Counts) bool {
			return true
		},
		OnStateChange: func(name string, from, to gobreaker.State) {
			t.Fatalf("no state transition expected but found %s -> %s", from, to)
		},
	})

	var called bool
	err := WithCircuitBreaker(context.Background(), cb,
		func(_ error) bool {
			// count every error
			return true
		},
		func() error {
			called = true
			return nil
		},
	)
	assert.True(t, called)
	assert.NoError(t, err)
}

func TestWithCircuitBreakerOpen(t *testing.T) {
	var transitions [][2]gobreaker.State
	cb := gobreaker.NewCircuitBreaker(gobreaker.Settings{
		Name:        "test_circuit_breaker",
		MaxRequests: 1,
		Interval:    20 * time.Millisecond,
		Timeout:     10 * time.Millisecond,
		ReadyToTrip: func(_ gobreaker.Counts) bool {
			// trip circuit on the first error
			return true
		},
		OnStateChange: func(name string, from, to gobreaker.State) {
			transitions = append(transitions, [2]gobreaker.State{from, to})
		},
	})

	countableErr := errors.New("this error counts against the circuit breaker")
	otherErr := errors.New("this error does not count against the circuit breaker")
	shouldCount := func(err error) bool {
		return errors.Is(err, countableErr)
	}

	var calls int
	doForError := func(errToReturn error) func() error {
		return func() error {
			calls++
			return errToReturn
		}
	}

	// these errors don't count against the CB
	err1 := WithCircuitBreaker(context.Background(), cb, shouldCount, doForError(otherErr))
	err2 := WithCircuitBreaker(context.Background(), cb, shouldCount, doForError(otherErr))
	// this error trips the circuit
	err3 := WithCircuitBreaker(context.Background(), cb, shouldCount, doForError(countableErr))
	// circuit is open so do is not called
	err4 := WithCircuitBreaker(context.Background(), cb, shouldCount, doForError(nil))

	// do should have not have been called the 4th time (when the circuit was open)
	assert.Equal(t, calls, 3)
	// expect 1 circuit transition from closed -> open
	require.Len(t, transitions, 1)
	transition := transitions[0]
	assert.Equal(t, transition[0], gobreaker.StateClosed)
	assert.Equal(t, transition[1], gobreaker.StateOpen)

	require.Error(t, err1)
	assert.EqualError(t, err1, otherErr.Error())
	require.Error(t, err2)
	assert.EqualError(t, err2, otherErr.Error())

	require.Error(t, err3)
	assert.EqualError(t, err3, countableErr.Error())

	require.Error(t, err4)
	assert.EqualError(t, err4, gobreaker.ErrOpenState.Error())
}
