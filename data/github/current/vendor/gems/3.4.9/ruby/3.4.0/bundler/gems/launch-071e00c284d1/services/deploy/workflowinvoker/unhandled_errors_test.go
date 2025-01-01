package workflowinvoker

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGuessIfEventTriggersRun(t *testing.T) {
	t.Run("schedule returns yes", func(tt *testing.T) {
		assert.Equal(tt, eventTriggersRunYes, guessIfEventTriggersRun(InvokingEvent{
			Name: "schedule",
		}))
	})
	t.Run("push returns likely", func(tt *testing.T) {
		assert.Equal(tt, eventTriggersRunLikely, guessIfEventTriggersRun(InvokingEvent{
			Name: "push",
		}))
	})
	t.Run("status returns unlikely", func(tt *testing.T) {
		assert.Equal(tt, eventTriggersRunUnlikely, guessIfEventTriggersRun(InvokingEvent{
			Name: "status",
		}))
	})

	t.Run("pull_request opened returns likely", func(tt *testing.T) {
		assert.Equal(tt, eventTriggersRunLikely, guessIfEventTriggersRun(InvokingEvent{
			Name:   "pull_request",
			Action: "opened",
		}))
	})
	t.Run("pull_request labeled returns unlikely", func(tt *testing.T) {
		assert.Equal(tt, eventTriggersRunUnlikely, guessIfEventTriggersRun(InvokingEvent{
			Name:   "pull_request",
			Action: "labeled",
		}))
	})

	t.Run("rerequested returns yes", func(tt *testing.T) {
		assert.Equal(tt, eventTriggersRunYes, guessIfEventTriggersRun(InvokingEvent{
			Name:   "status",
			Action: "rerequested",
		}))
	})
}
