package queueworker

import (
	context "context"
	"testing"

	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/testutils"
)

type serviceSuite struct {
	suite.Suite
	testLogger testutils.RecordingLogger
}

func TestService(t *testing.T) {
	suite.Run(t, new(serviceSuite))
}

func (s *serviceSuite) SetupTest() {
	s.testLogger = testutils.NewRecordingLogger()
}

func (s *serviceSuite) Test_Service_RunAndShutdown() {
	svc, err := New(
		QueueWorkerConfig{
			NumWorkers: 1,
		},
		&MockJobProcessor{},
		observability.New(s.testLogger.Logger, statter.NullStatter()),
		testutils.NewNoopBreaker(),
		aqueduct.NewFactory(nil),
	)
	s.NoError(err)

	go svc.Run(context.Background())
	svc.Shutdown(context.Background())

	s.assertLogged("starting worker 0")
	s.assertLogged("shutdown triggered gracefully")
}

func (s *serviceSuite) assertLogged(message string) {
	s.Contains(s.testLogger.String(), message)
}
