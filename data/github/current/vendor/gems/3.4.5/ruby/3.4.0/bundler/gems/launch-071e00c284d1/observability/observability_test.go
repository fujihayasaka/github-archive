package observability

import (
	"testing"
	"time"

	"github.com/stretchr/testify/suite"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
)

func TestEncoder(t *testing.T) {
	suite.Run(t, new(observabilityTestSuite))
}

type observabilityTestSuite struct {
	suite.Suite
}

func (s *observabilityTestSuite) Test_CopyCheckpoints() {
	obs1 := New(logger.TestLogger(), statter.NullStatter())
	now := time.Now().UTC()

	var key checkpointKey = "chckpt-1"
	obs1.AddCheckpoint(key, now)

	obs2 := CopyCheckpoints(obs1)

	// Now change the obs1 checkpoint
	later := now.Add(time.Minute)
	obs1.AddCheckpoint(key, later)

	// obs2 has original time
	v, ok := obs2.checkpoints.Load(key)
	s.True(ok)
	s.Equal(now, v)

	// obs1 is the changed value
	v, ok = obs1.checkpoints.Load(key)
	s.True(ok)
	s.Equal(later, v)

}
