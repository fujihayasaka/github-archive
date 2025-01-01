// Package jobs contains all the jobs that the scheduler can run.
package jobs

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"testing"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	statsmocks "github.com/github/go-stats/mocks"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/testing/mocks"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

type emissionDispatcherJobTestSuite struct {
	cfg        *config.Config
	dispatcher *EmissionDispatcherJob
	suite.Suite
	mockAqueductClient *mocks.MockAqueductClient
	mockStatter        *statsmocks.Client
}

func (e *emissionDispatcherJobTestSuite) SetupTest() {
	cfg, _ := config.Load()
	logger := log.NewNullLogger()

	e.cfg = cfg
	e.mockAqueductClient = &mocks.MockAqueductClient{}
	jobby := &jobs.Jobby{Cfg: cfg, AqueductClient: e.mockAqueductClient}
	e.mockStatter = &statsmocks.Client{}
	e.mockStatter.Mock.On("WithTags", mock.AnythingOfType("stats.Tags")).Return(e.mockStatter)
	e.mockStatter.Mock.On("Counter", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Return(nil)
	e.mockStatter.Mock.On("Timing", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("time.Duration")).Return(nil)
	e.dispatcher = NewEmissionDispatcherJob(context.Background(), e.cfg, logger, e.mockStatter, jobby)
}

func (e *emissionDispatcherJobTestSuite) prepareMockSend(jobPayload []byte, returnID string, returnErr error) {
	e.mockAqueductClient.On(
		"Send",
		e.dispatcher.ctx,
		mock.MatchedBy(func(j aqueduct.Job) bool {
			return j.App == e.cfg.AqueductApp &&
				j.Queue == queues.QueueScheduleEmissions &&
				j.Headers[jobs.JobNameHeader] == jobs.JobNameScheduleEmissions &&
				bytes.Equal(j.Payload, jobPayload)
		}),
		mock.AnythingOfType("[]aqueduct.SendOption"),
	).Return(returnID, returnErr).Once()
}

func (e *emissionDispatcherJobTestSuite) TestEmissionDispatcherJob_RunSuccess() {
	jobID := "jobID-1234"
	secondsSinceEpoch := int64(1728675888)
	emissionsJob := &models.ScheduleEmissionsJob{UsageTime: secondsSinceEpoch}
	jobPayload, err := json.Marshal(emissionsJob)
	e.Require().NoError(err)

	e.prepareMockSend(jobPayload, jobID, nil)

	err = e.dispatcher.Run(secondsSinceEpoch)
	e.Require().NoError(err)
	e.mockAqueductClient.AssertExpectations(e.T())
	e.mockStatter.AssertCalled(e.T(), "Counter", "emission_dispatcher.job.processed", stats.Tags{}, int64(1))
}

func (e *emissionDispatcherJobTestSuite) TestEmissionDispatcherJob_FailSendJob() {
	secondsSinceEpoch := int64(1728675888)
	emissionsJob := &models.ScheduleEmissionsJob{UsageTime: secondsSinceEpoch}
	jobPayload, err := json.Marshal(emissionsJob)
	e.Require().NoError(err)

	e.prepareMockSend(jobPayload, "", errors.New("send error"))

	err = e.dispatcher.Run(secondsSinceEpoch)
	fmt.Println(err.Error())
	e.Require().Error(err)
	e.Require().Contains(err.Error(), "send error")
	e.mockAqueductClient.AssertExpectations(e.T())
	e.mockStatter.AssertNotCalled(e.T(), "Counter", "emission_dispatcher.job.processed", mock.Anything, mock.Anything)
}

func TestEmissionDispatcherJobTestSuite(t *testing.T) {
	suite.Run(t, new(emissionDispatcherJobTestSuite))
}
