package abuse_test

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/services/receiver/abuse"
)

type StatusSuite struct {
	suite.Suite
	svc      *abuse.StatusServicer
	deployer *deploy.MockLaunchDeploymentService
}

func TestStatusSuite(t *testing.T) {
	suite.Run(t, new(StatusSuite))
}

func (s *StatusSuite) SetupTest() {
	s.deployer = &deploy.MockLaunchDeploymentService{}
	s.svc = abuse.NewServicer(
		logger.NullLogger(),
		statter.NullStatter(),
		s.deployer)
}

func (s *StatusSuite) TestThatServiceCanAcceptRequest() {
	s.deployer.On(
		"AbuseStatus",
		mock.Anything,
		mock.Anything,
	).Return(
		&deploy.AbuseStatusResponse{ValidSignature: true},
		nil,
	)
	res := httptest.NewRecorder()
	req := s.getAbuseStatusRequest([]byte(`{
		"reputationScore": 25,
		"buildId": 1234,
		"isConstant": false,
		"firstDate": "2019-08-25T21:46:47Z",
		"evaluationDate": "2019-08-28T21:46:47Z",
		"hasPrivateProject": false,
		"maxParallelism": 11,
		"runCount": 238,
		"runAverage": 8,
		"runDeviation": 1,
		"runDensity": 85,
		"maliciousProcessDensity": 0,
		"alteredHostsFileDensity": 0,
		"suspiciousSourceDensity": 0
	}`))
	req = req.WithContext(measurehttp.WithThresholdLogging(req.Context()))
	s.svc.HandleAbuseStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.deployer.AssertExpectations(s.T())
}

func (s *StatusSuite) TestThatServiceCanAcceptAbuseDetectionStatusRequest() {
	s.deployer.On(
		"AbuseDetectionStatus",
		mock.Anything,
		mock.Anything,
	).Return(
		&deploy.AbuseStatusResponse{ValidSignature: true},
		nil,
	)
	res := httptest.NewRecorder()
	req := s.getAbuseDetectionStatusRequest([]byte(`{
		"score": 25,
		"maxParallelism": 11,
		"firstBuildDate": "2019-08-25T21:46:47Z",
		"totalJobs": 12,
		"inProgressJobs": 6,
		"numberOfLongRunningRequests": 2,
		"accountLifetimeInMinutes": 100,
		"totalJobRuntime": 60,
		"inProgressJobRuntime": 20,
		"hasMaxConcurrentLongRunningBuilds": false
	}`))
	req = req.WithContext(measurehttp.WithThresholdLogging(req.Context()))
	s.svc.HandleAbuseDetectionStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.deployer.AssertExpectations(s.T())
}

func (s *StatusSuite) TestThatServiceRejectsRequestsWithInvalidSignatures() {
	s.deployer.On(
		"AbuseStatus",
		mock.Anything,
		mock.Anything,
	).Return(
		&deploy.AbuseStatusResponse{ValidSignature: false},
		nil,
	)
	res := httptest.NewRecorder()
	req := s.getAbuseStatusRequest([]byte(`{
		"reputationScore": 25,
		"buildId": 1234,
		"isConstant": false,
		"firstDate": "2019-08-25T21:46:47Z",
		"evaluationDate": "2019-08-28T21:46:47Z",
		"hasPrivateProject": false,
		"maxParallelism": 11,
		"runCount": 238,
		"runAverage": 8,
		"runDeviation": 1,
		"runDensity": 85,
		"maliciousProcessDensity": 0,
		"alteredHostsFileDensity": 0,
		"suspiciousSourceDensity": 0
	}`))
	req = req.WithContext(measurehttp.WithThresholdLogging(req.Context()))
	s.svc.HandleAbuseStatus(res, req)
	s.Equal(http.StatusUnauthorized, res.Code)
	s.deployer.AssertExpectations(s.T())
}

func (s *StatusSuite) TestThatServiceRejectsAbuseDetectionStatusRequestsWithInvalidSignatures() {
	s.deployer.On(
		"AbuseDetectionStatus",
		mock.Anything,
		mock.Anything,
	).Return(
		&deploy.AbuseStatusResponse{ValidSignature: false},
		nil,
	)
	res := httptest.NewRecorder()
	req := s.getAbuseStatusRequest([]byte(`{
		"score": 25,
		"maxParallelism": 11,
		"firstBuildDate": "2019-08-25T21:46:47Z",
		"totalJobs": 12,
		"inProgressJobs": 6,
		"numberOfLongRunningRequests": 2,
		"accountLifetimeInMinutes": 100,
		"totalJobRuntime": 60,
		"inProgressJobRuntime": 20,
		"hasMaxConcurrentLongRunningBuilds": false
	}`))
	req = req.WithContext(measurehttp.WithThresholdLogging(req.Context()))
	s.svc.HandleAbuseDetectionStatus(res, req)
	s.Equal(http.StatusUnauthorized, res.Code)
	s.deployer.AssertExpectations(s.T())
}

func (s *StatusSuite) getAbuseStatusRequest(body []byte) *http.Request {
	req := httptest.NewRequest(http.MethodPost, "/actions/abuse/status", bytes.NewReader(body))
	req.Header.Add("Authorization", "HMAC-SHA512 Signature=null")
	req.Header.Add("Content-Type", "application/json")
	return req
}

func (s *StatusSuite) getAbuseDetectionStatusRequest(body []byte) *http.Request {
	req := httptest.NewRequest(http.MethodPost, "/actions/abuse-detection/status", bytes.NewReader(body))
	req.Header.Add("Authorization", "HMAC-SHA512 Signature=null")
	req.Header.Add("Content-Type", "application/json")
	return req
}
