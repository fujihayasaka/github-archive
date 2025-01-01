package queueworker

import (
	context "context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/utils/clock"

	mock "github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/panicmultierrgroup"
	"github.com/github/launch/pkg/processors/webhook"
	"github.com/github/launch/services/deploy/workflowinvoker"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/testutils"
)

type processorSuite struct {
	suite.Suite
	mockClient       *aqueduct.MockClient
	mockJobProcessor *MockJobProcessor
	testLogger       testutils.RecordingLogger
	clock            *clock.Mock
	worker           *worker
}

func TestProcessor(t *testing.T) {
	suite.Run(t, new(processorSuite))
}

func (s *processorSuite) SetupTest() {
	worker, mocks := newWorkerWithMocks()

	s.mockClient = mocks.aqueductClient
	s.mockJobProcessor = mocks.jobProcessor
	s.testLogger = mocks.logger
	s.clock = mocks.clock
	s.worker = worker
}

func (s *processorSuite) TearDownTest() {
	s.mockClient.AssertExpectations(s.T())
	s.mockJobProcessor.AssertExpectations(s.T())
}

func (s *processorSuite) Test_Work_ProperlyWorkJob() {
	// The receive request is sent, getting us a usable payload to parse

	recvResult := &aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			Payload: []byte("{\"guid\":\"a-webhook-delivery-id\", \"event\":\"an-event\", \"payload\":{\"some-key\":\"some-val\"}}"),
		},
	}
	s.mockClient.On("Receive", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(recvResult, time.Duration(0), nil)
	s.mockClient.On("ID").Return(s.worker.ID)

	// The job is processed with the expected payload
	s.mockJobProcessor.On("Process", mock.Anything, mock.Anything, mock.MatchedBy(func(jobPayload []byte) bool {
		var j webhook.Job
		json.Unmarshal(jobPayload, &j)

		s.Equal("a-webhook-delivery-id", j.WebhookDeliveryID)
		s.Equal("an-event", j.Event)
		return true
	}), mock.Anything).Return(nil)

	// The payload is acked
	s.mockClient.On("Ack", mock.Anything, mock.AnythingOfType("aqueduct.Job"), aqueduct.AckSuccess).Return(nil)

	ctx := context.WithValue(
		context.Background(),
		reqmeta.RMDContextKey,
		reqmeta.NewRequestMetadata()) // We need request metadata to have mw.LogWith work

	res, nextRecvAt := s.worker.Work(ctx)
	s.Equal(resultSuccess, res)
	s.Equal(s.clock.Now(), nextRecvAt)
}

func (s *processorSuite) Test_ProcessJob_extendsRetryWindow() {
	errGroup := &panicmultierrgroup.Group{}
	errGroup.Go(func() error {
		return terrors.NewRetryableDuration("I lost my keys", 10*time.Minute)
	})
	errGroup.Go(func() error {
		return errors.New("Database error")
	})
	errGroup.Go(func() error {
		return terrors.NewRetryableDuration("I lost my wallet", 15*time.Minute)
	})
	multierror := errGroup.Wait()

	tests := []struct {
		name           string
		err            error
		isRetryable    bool
		maxRetryWindow time.Duration
	}{
		{
			name:           "Basic error not retryable",
			err:            errors.New("some error"),
			isRetryable:    false,
			maxRetryWindow: defaultMaxRetryWindow,
		},
		{
			name:           "Explicitly unretryable error",
			err:            &permanentError{errors.New("400 Invalid Workflow Syntax")},
			isRetryable:    false,
			maxRetryWindow: defaultMaxRetryWindow,
		},
		{
			name:           "Retryable without duration",
			err:            terrors.NewRetryable("database timeout"),
			isRetryable:    true,
			maxRetryWindow: defaultMaxRetryWindow,
		},
		{
			name:           "Retryable with duration",
			err:            terrors.NewRetryableDuration("database timeout", 10*time.Minute),
			isRetryable:    true,
			maxRetryWindow: 10 * time.Minute,
		},
		{
			name:           "Multiple RetryableDuration errors",
			err:            multierror,
			isRetryable:    true,
			maxRetryWindow: 15 * time.Minute,
		},
		{
			name:           "Wrapped multiple RetryableDuration errors",
			err:            fmt.Errorf("I can't join you for dinner: %w", fmt.Errorf("I can't leave the house: %w", multierror)),
			isRetryable:    true,
			maxRetryWindow: 15 * time.Minute,
		},
	}

	for _, tc := range tests {
		s.Run(tc.name, func() {
			s.SetupTest() // Need to reset the mocks for this subtest

			// The job is processed with the expected payload
			s.mockJobProcessor.On("Process", mock.Anything, mock.Anything, mock.MatchedBy(func(jobPayload []byte) bool {
				var j webhook.Job
				json.Unmarshal(jobPayload, &j)

				s.Equal("a-webhook-delivery-id", j.WebhookDeliveryID)
				s.Equal("an-event", j.Event)
				return true
			}), mock.Anything).Return(tc.err)

			ctx := context.WithValue(
				context.Background(),
				reqmeta.RMDContextKey,
				reqmeta.NewRequestMetadata()) // We need request metadata to have mw.LogWith work

			recvResult := &aqueduct.ReceiveResult{
				Job: aqueduct.Job{
					ID:      "a-jobId",
					Payload: []byte("{\"guid\":\"a-webhook-delivery-id\", \"event\":\"an-event\", \"payload\":{\"some-key\":\"some-val\"}}"),
					Queue:   "a-queue",
				},
			}

			ja := &jobAttempt{
				attemptNumber:         1,
				originalAqueductJobID: "aq-job-123",
				retryUntil:            time.Now().Add(time.Minute),
			}
			ja.originalReceiveAt = ja.retryUntil.Add(-defaultMaxRetryWindow)

			retryable, err := s.worker.processJob(ctx, recvResult, time.Now(), time.Now(), ja, false)
			s.NoError(err)
			s.Equal(tc.isRetryable, retryable)
			s.Equal(tc.maxRetryWindow, ja.retryUntil.Sub(ja.originalReceiveAt))

			s.TearDownTest() // assert expectations, including the number of calls to Send.
		})
	}
}

// Verify ProcessJob sends heartbeats while processing a long-running job.
func (s *processorSuite) Test_ProcessJob_SendsHeartbeats() {
	s.test_heartbeats(false)
}

// Verify ProcessJob stops sending heartbeats following a panic.
func (s *processorSuite) Test_ProcessJob_StopsHeartbeatsAfterPanic() {
	s.test_heartbeats(true)
}

func (s *processorSuite) test_heartbeats(testPanic bool) {
	queueName := "a-queue"
	jobId := "a-jobId"

	s.mockClient.On("Heartbeat", mock.Anything, mock.AnythingOfType("aqueduct.Job")).Return(nil).Times(12)

	recvResult := &aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			ID:      jobId,
			Payload: []byte("{\"guid\":\"a-webhook-delivery-id\", \"event\":\"an-event\", \"payload\":{\"some-key\":\"some-val\"}}"),
			Queue:   queueName,
		},
	}

	jobProcessorDone := make(chan time.Time)

	// The job is processed with the expected payload
	call := s.mockJobProcessor.On("Process", mock.Anything, mock.Anything, mock.MatchedBy(func(jobPayload []byte) bool {
		var j webhook.Job
		json.Unmarshal(jobPayload, &j)

		s.Equal("a-webhook-delivery-id", j.WebhookDeliveryID)
		s.Equal("an-event", j.Event)
		// s.Equal(map[string]interface{}{"some-key": "some-val"}, j.Payload)
		return true
	}), mock.Anything).WaitUntil(jobProcessorDone)

	if testPanic {
		call.Panic("processing failed!")
	} else {
		call.Return(nil)
	}

	ctx := context.WithValue(
		context.Background(),
		reqmeta.RMDContextKey,
		reqmeta.NewRequestMetadata()) // We need request metadata to have mw.LogWith work

	go func() {
		// wait for (*worker).sendHeartbeatPeriodically to start and create a Ticker.
		s.clock.WaitForTickerCount(1)

		// move the clock forward so heartbeats are sent.
		s.clock.Add(12 * s.worker.cfg.HeartbeatAttemptInterval)

		// give (*worker).sendHeartbeatPeriodically time to select the ticks instead of ctx.Done.
		s.clock.WaitForTickersToDrain()

		// have our long-running job return.
		close(jobProcessorDone)
	}()

	ja := &jobAttempt{attemptNumber: 1}

	retryable, err := s.worker.processJob(ctx, recvResult, time.Now(), time.Now(), ja, false)
	if testPanic {
		s.True(retryable)
		s.Error(err)
	} else {
		s.False(retryable)
		s.NoError(err)
	}

	// Confirm 12 heartbeats were sent.
	s.mockClient.AssertExpectations(s.T())

	// Move the clock forward some more intervals and confirm no additional heartbeats are sent.
	// If the heartbeat goroutine isn't properly canceled, AssertExpectations will fail with "assert: mock: The method has been called over 12 times."
	s.clock.Add(5 * s.worker.cfg.HeartbeatAttemptInterval)
	s.mockClient.AssertExpectations(s.T())
}

func (s *processorSuite) Test_SendHeartbeatNoErrorOnContextCancel() {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	s.mockClient.On("Heartbeat", mock.Anything, mock.Anything).Return(nil, twirp.InternalErrorWith(ctx.Err()))

	recvResult := &aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			Payload: nil,
		},
	}

	err := s.worker.sendHeartbeat(ctx, recvResult)
	s.Nil(err)
}

func (s *processorSuite) Test_Work_NoJobFound() {
	// The receive request is sent, returning an empty payload
	recvResult := &aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			Payload: nil,
			App:     "app",
		},
	}
	s.mockClient.On("Receive", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(recvResult, time.Duration(0), nil)
	s.mockClient.On("ID").Return(s.worker.ID)

	// Nothing to ack
	s.mockClient.AssertNotCalled(s.T(), "Ack")

	ctx := context.Background()
	res, nextRecvAt := s.worker.Work(ctx)
	s.Equal(resultNoneFound, res)
	s.Equal(s.clock.Now(), nextRecvAt)
}

func (s *processorSuite) Test_Work_NilAqueductResponse() {
	s.mockClient.On("Receive", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, time.Duration(0), nil)
	s.mockClient.On("ID").Return(s.worker.ID)

	ctx := context.Background()
	res, nextRecvAt := s.worker.Work(ctx)
	s.Equal(resultNoneFound, res)
	s.Equal(s.clock.Now(), nextRecvAt)
}

func (s *processorSuite) Test_Work_AddsBackoffSecondsToTime() {
	// Simulate Aqueduct asking a worker to wait several seconds before checking the queue again
	backoff := 42 * time.Second
	s.mockClient.On("Receive", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, backoff, nil)
	s.mockClient.On("ID").Return(s.worker.ID)

	ctx := context.Background()
	res, nextRecvAt := s.worker.Work(ctx)
	s.Equal(resultNoneFound, res)
	s.Equal(s.clock.Now().Add(backoff), nextRecvAt)
}

func (s *processorSuite) Test_Work_HandleJobPanic() {
	// The receive request is sent, returning an empty payload
	recvResult := &aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			Payload: []byte("{\"guid\":\"a-webhook-delivery-id\", \"event\":\"an-event\", \"payload\":{\"some-key\":\"some-val\"}}"),
		},
	}
	s.mockClient.On("Receive", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(recvResult, time.Duration(0), nil)
	s.mockClient.On("Send", mock.Anything, mock.Anything, mock.Anything).Return("new-aqueduct-job-id", nil)
	s.mockClient.On("Ack", mock.Anything, mock.Anything, aqueduct.AckSuccess).Return(nil)

	s.mockClient.On("ID").Return(s.worker.ID)

	s.mockJobProcessor.On("Process", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Panic("processing failed!")

	s.NotPanics(func() {
		ctx := context.Background()
		res, nextRecvAt := s.worker.Work(ctx)
		// The result should be success as the job will be retried
		s.Equal(resultSuccess, res)
		s.Equal(s.clock.Now(), nextRecvAt)
	})
}

// The job should be requeued only if the error is retryable.
func (s *processorSuite) Test_Work_JobRequeuedIfErrorRetryable() {
	tests := []struct {
		name        string
		err         error
		isRetryable bool
	}{
		{
			name:        "Not requeued following basic error",
			err:         errors.New("some error"),
			isRetryable: false,
		},
		{
			name:        "Not requeued following explicitly unretryable error",
			err:         &permanentError{errors.New("400 Invalid Workflow Syntax")},
			isRetryable: false,
		},
		{
			name:        "Requeued following retryable error",
			err:         terrors.NewRetryable("database timeout"),
			isRetryable: true,
		},
		{
			name:        "Requeued following RetryableDurationError",
			err:         terrors.NewRetryableDuration("database timeout", 10*time.Minute),
			isRetryable: true,
		},
		{
			name:        "Requeued following an error chain containing retryable error",
			err:         errors.Wrap(errors.Wrap(terrors.NewRetryable("database timeout"), "failed to check for existing workflow build"), "failed to queue a build for awesome.yml"),
			isRetryable: true,
		},
	}

	for _, tc := range tests {
		s.Run(tc.name, func() {
			s.SetupTest() // Need to reset the mocks for this subtest
			w := &worker{
				cfg: QueueWorkerConfig{
					AqueductApp:              "AqueductApp",
					AqueductQueues:           []string{"queue1", "queue2"},
					AqueductTimeoutMs:        4000,
					HeartbeatAttemptInterval: time.Second,
					MaxTimeWithoutHeartbeat:  time.Minute,
				},
				ID:    "worker_id",
				obs:   observability.New(s.testLogger.Logger, statter.NullStatter()),
				aq:    s.mockClient,
				jp:    s.mockJobProcessor,
				clock: clock.NewMock(1000),
			}

			// The receive request is sent, getting us a usable payload to parse
			recvResult := &aqueduct.ReceiveResult{
				Job: aqueduct.Job{
					Payload: []byte("{\"guid\":\"a-webhook-delivery-id\", \"event\":\"an-event\", \"payload\":{\"some-key\":\"some-val\"}}"),
				},
			}
			s.mockClient.On("Receive", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(recvResult, time.Duration(0), nil)
			s.mockClient.On("ID").Return(w.ID)
			s.mockClient.On("Ack", mock.Anything, mock.Anything, aqueduct.AckSuccess).Return(nil)

			if tc.isRetryable {
				s.mockClient.On("Send", mock.Anything, mock.Anything, mock.Anything).Return("new-aqueduct-job-id", nil)
			}

			// The job is processed with the expected payload
			s.mockJobProcessor.On("Process", mock.Anything, mock.Anything, mock.MatchedBy(func(jobPayload []byte) bool {
				var j webhook.Job
				json.Unmarshal(jobPayload, &j)
				s.Equal("a-webhook-delivery-id", j.WebhookDeliveryID)
				s.Equal("an-event", j.Event)
				return true
			}), false).Return(tc.err)

			ctx := context.WithValue(
				context.Background(),
				reqmeta.RMDContextKey,
				reqmeta.NewRequestMetadata()) // We need request metadata to have mw.LogWith work

			res, nextRecvAt := w.Work(ctx)
			s.Equal(resultSuccess, res)
			s.Equal(s.clock.Now(), nextRecvAt)

			s.assertLogged("JobProcessor failed")
			s.assertLogged(fmt.Sprintf("is_retryable=%v", tc.isRetryable))
			s.TearDownTest() // assert expectations, including the number of calls to Send.
		})
	}
}

// Jobs shouldn't be requeued if there are user errors
func (s *processorSuite) Test_Work_JobDoesntRequeueOnUserError() {
	tests := []struct {
		name            string
		err             error
		requeueExpected bool
	}{
		{
			name:            "Job requeued following retryable error",
			err:             terrors.NewRetryable("database timeout"),
			requeueExpected: true,
		},
		{
			name:            "Job requeued following retryable, non-user error",
			err:             &testSystemError{errors.New("System error")},
			requeueExpected: true,
		},
		{
			name:            "Job not requeued following user error",
			err:             &testUserError{errors.New("Email not verified")},
			requeueExpected: false,
		},
		{
			name:            "Job not requeued following an error caused by a user error",
			err:             errors.Wrap(errors.Wrap(&testUserError{errors.New("Email not verified")}, "failed to check for existing workflow build"), "failed to queue a build for awesome.yml"),
			requeueExpected: false,
		},
		{
			name: "Job requeued for multiple errors where some are user errors",
			err: workflowinvoker.NewMultiWorkflowStartError([]*workflowinvoker.WorkflowStartErr{
				workflowinvoker.NewWorkflowStartError(&workflowinvoker.WorkflowStartErrorContext{}, errors.New("system error"), ""),
				workflowinvoker.NewWorkflowStartError(&workflowinvoker.WorkflowStartErrorContext{}, terrors.NewUserError("syntax error"), ""),
			}),
			requeueExpected: true,
		},
		{
			name: "Job not requeued for multiple errors where all are user errors",
			err: workflowinvoker.NewMultiWorkflowStartError([]*workflowinvoker.WorkflowStartErr{
				workflowinvoker.NewWorkflowStartError(&workflowinvoker.WorkflowStartErrorContext{}, terrors.NewUserError("syntax error in workflow A"), ""),
				workflowinvoker.NewWorkflowStartError(&workflowinvoker.WorkflowStartErrorContext{}, terrors.NewUserError("syntax error in workflow B"), ""),
			}),
			requeueExpected: false,
		},
	}

	for _, tc := range tests {
		s.Run(tc.name, func() {
			s.SetupTest() // Need to reset the mocks for this subtest
			w := &worker{
				cfg: QueueWorkerConfig{
					AqueductApp:              "AqueductApp",
					AqueductQueues:           []string{"queue1", "queue2"},
					AqueductTimeoutMs:        4000,
					HeartbeatAttemptInterval: time.Second,
					MaxTimeWithoutHeartbeat:  time.Minute,
				},
				ID:    "worker_id",
				obs:   observability.New(s.testLogger.Logger, statter.NullStatter()),
				aq:    s.mockClient,
				jp:    s.mockJobProcessor,
				clock: clock.NewMock(1000),
			}

			// The receive request is sent, getting us a usable payload to parse
			recvResult := &aqueduct.ReceiveResult{
				Job: aqueduct.Job{
					Payload: []byte("{\"guid\":\"a-webhook-delivery-id\", \"event\":\"an-event\", \"payload\":{\"some-key\":\"some-val\"}}"),
				},
				MaxDeliveryAttempts: 3,
				DeliveryAttempt:     1,
			}
			s.mockClient.On("Receive", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(recvResult, time.Duration(0), nil)
			s.mockClient.On("ID").Return(w.ID)
			s.mockClient.On("Ack", mock.Anything, mock.Anything, aqueduct.AckSuccess).Return(nil)

			if tc.requeueExpected {
				s.mockClient.On("Send", mock.Anything, mock.Anything, mock.Anything).Return("new-aqueduct-job-id", nil)
			}

			// The job is processed with the expected payload
			s.mockJobProcessor.On("Process", mock.Anything, mock.Anything, mock.MatchedBy(func(jobPayload []byte) bool {
				var j webhook.Job
				json.Unmarshal(jobPayload, &j)
				s.Equal("a-webhook-delivery-id", j.WebhookDeliveryID)
				s.Equal("an-event", j.Event)
				return true
			}), false).Return(tc.err)

			ctx := context.WithValue(
				context.Background(),
				reqmeta.RMDContextKey,
				reqmeta.NewRequestMetadata()) // We need request metadata to have mw.LogWith work

			res, nextRecvAt := w.Work(ctx)
			s.Equal(resultSuccess, res)
			s.Equal(s.clock.Now(), nextRecvAt)

			if tc.requeueExpected {
				s.assertLogged("JobProcessor failed")
				s.refuteLogged("JobProcessor resulted in user error")
			} else {
				s.assertLogged("JobProcessor resulted in user error")
				s.refuteLogged("JobProcessor failed")
			}

			s.TearDownTest() // assert expectations, including the number of calls to Send.
		})
	}
}

// The job shouldn't be requeued when Process is passed true for isFinalAttempt.
func (s *processorSuite) Test_Work_JobNotRequeuedOnFinalAttempt() {
	mc := clock.NewMock(100)
	soon := mc.Now().Add(30 * time.Second)
	later := mc.Now().Add(180 * time.Second)

	tests := []struct {
		name                 string
		finalAttemptTime     time.Time
		finalAttemptExpected bool
		requeueExpected      bool
	}{
		{
			name:                 "intermediate attempt",
			finalAttemptTime:     later,
			finalAttemptExpected: false,
			requeueExpected:      true,
		},
		{
			name:                 "final attempt",
			finalAttemptTime:     soon,
			finalAttemptExpected: true,
			requeueExpected:      false,
		},
	}

	// A retryable error causes the job to be re-attempted. See other tests.
	retryableErr := terrors.NewRetryable("database timeout")

	// Used to verify DeliverAt has some backoff. See Test_backoff for full testing
	minBackoff := 15 * time.Second

	for _, tc := range tests {
		s.Run(tc.name, func() {
			s.SetupTest() // Need to reset the mocks for this subtest
			mc := clock.NewMock(1000)
			w := &worker{
				cfg: QueueWorkerConfig{
					AqueductApp:              "AqueductApp",
					AqueductQueues:           []string{"queue1", "queue2"},
					AqueductTimeoutMs:        4000,
					HeartbeatAttemptInterval: time.Second,
					MaxTimeWithoutHeartbeat:  time.Minute,
				},
				ID:    "worker_id",
				obs:   observability.New(s.testLogger.Logger, statter.NullStatter()),
				aq:    s.mockClient,
				jp:    s.mockJobProcessor,
				clock: mc,
			}

			ja := &jobAttempt{
				originalAqueductJobID: "orig-aq-job-id",
				attemptNumber:         2,
				retryUntil:            tc.finalAttemptTime,
			}

			// The receive request is sent, getting us a usable payload to parse
			recvResult := &aqueduct.ReceiveResult{
				Job: aqueduct.Job{
					Payload: []byte("{\"guid\":\"a-webhook-delivery-id\", \"event\":\"an-event\", \"payload\":{\"some-key\":\"some-val\"}}"),
				},
			}

			ja.addAttemptDetails(&recvResult.Job)

			s.mockClient.On("Receive", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(recvResult, time.Duration(0), nil)
			s.mockClient.On("ID").Return(w.ID)
			s.mockClient.On("Ack", mock.Anything, mock.Anything, aqueduct.AckSuccess).Return(nil)

			if tc.requeueExpected {
				s.mockClient.On("Send", mock.Anything, mock.MatchedBy(func(j aqueduct.Job) bool {
					s.NotZero(j.DeliverAt)
					s.Greater(j.DeliverAt.Sub(time.Now()), minBackoff)
					return true
				}), mock.Anything).Return("new-aqueduct-job-id", nil)
			}

			// The job is processed with the expected payload
			s.mockJobProcessor.On("Process", mock.Anything, mock.Anything, mock.MatchedBy(func(jobPayload []byte) bool {
				var j webhook.Job
				json.Unmarshal(jobPayload, &j)
				s.Equal("a-webhook-delivery-id", j.WebhookDeliveryID)
				s.Equal("an-event", j.Event)
				return true
			}), tc.finalAttemptExpected).Return(retryableErr)

			ctx := context.WithValue(
				context.Background(),
				reqmeta.RMDContextKey,
				reqmeta.NewRequestMetadata()) // We need request metadata to have mw.LogWith work

			res, nextRecvAt := w.Work(ctx)
			s.Equal(resultSuccess, res)
			s.Equal(s.clock.Now(), nextRecvAt)

			s.assertLogged("JobProcessor failed")
			s.assertLogged("is_retryable=true")

			if tc.requeueExpected {
				s.assertLogged("aqueduct job requeued")
				s.refuteLogged("Job can't be retried. No retries remaining.")
			} else {
				s.assertLogged("Job can't be retried. No retries remaining.")
				s.refuteLogged("aqueduct job requeued")
			}

			s.TearDownTest()
		})
	}
}

func (s *processorSuite) Test_Work_JobNotAckedWhenRequeuingFails() {
	// A retryable error causes the job to be re-attempted. See other tests.
	retryableErr := terrors.NewRetryable("database timeout")

	// The receive request is sent, returning an empty payload
	recvResult := &aqueduct.ReceiveResult{
		Job: aqueduct.Job{
			Payload: []byte("{\"guid\":\"a-webhook-delivery-id\", \"event\":\"an-event\", \"payload\":{\"some-key\":\"some-val\"}}"),
		},
	}
	s.mockClient.On("Receive", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(recvResult, time.Duration(0), nil)
	s.mockClient.On("Send", mock.Anything, mock.Anything, mock.Anything).Return("", errors.New("Aqueduct says no"))
	s.mockClient.On("ID").Return(s.worker.ID)
	s.mockClient.AssertNotCalled(s.T(), "Ack")

	s.mockJobProcessor.On("Process", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(retryableErr)

	ctx := context.WithValue(
		context.Background(),
		reqmeta.RMDContextKey,
		reqmeta.NewRequestMetadata()) // We need request metadata to have mw.LogWith work

	res, nextRecvAt := s.worker.Work(ctx)
	s.Equal(resultAqueductError, res)
	s.Equal(s.clock.Now(), nextRecvAt)

	s.assertLogged("JobProcessor failed")
	s.assertLogged("is_retryable=true")
}

func (s *processorSuite) assertLogged(message string) {
	s.Contains(s.testLogger.String(), message)
}

func (s *processorSuite) refuteLogged(message string) {
	s.NotContains(s.testLogger.String(), message)
}

type mocks struct {
	aqueductClient *aqueduct.MockClient
	jobProcessor   *MockJobProcessor
	logger         testutils.RecordingLogger
	clock          *clock.Mock
}

func newWorkerWithMocks() (*worker, *mocks) {
	mocks := &mocks{}

	mocks.aqueductClient = &aqueduct.MockClient{}
	mocks.jobProcessor = &MockJobProcessor{}
	mocks.logger = testutils.NewRecordingLogger()
	mocks.clock = clock.NewMock(1000)

	worker := &worker{
		cfg: QueueWorkerConfig{
			AqueductApp:              "AqueductApp",
			AqueductQueues:           []string{"queue1", "queue2"},
			AqueductTimeoutMs:        4000,
			HeartbeatAttemptInterval: time.Second,
			MaxTimeWithoutHeartbeat:  time.Minute,
		},
		ID:    "worker_id",
		obs:   observability.New(mocks.logger.Logger, statter.NullStatter()),
		aq:    mocks.aqueductClient,
		jp:    mocks.jobProcessor,
		clock: mocks.clock,
	}

	return worker, mocks
}

type permanentError struct {
	error
}

func (p *permanentError) IsRetryable() bool {
	return false
}

type testSystemError struct {
	error
}

func (p *testSystemError) IsUserError() bool {
	return false
}

func (p *testSystemError) IsRetryable() bool {
	return true
}

type testUserError struct {
	error
}

func (p *testUserError) IsUserError() bool {
	return true
}
