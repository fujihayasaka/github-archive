package receiver

import (
	"testing"
	"time"

	"github.com/stretchr/testify/suite"
)

type receiverURLTestSuite struct {
	suite.Suite
}

func TestReceiverURLTestSuite(t *testing.T) {
	suite.Run(t, new(receiverURLTestSuite))
}

func (s *receiverURLTestSuite) TestGetJobStatusCallbackURL() {
	var url string
	var err error

	ts, err := time.Parse(time.RFC3339Nano, "2014-11-12T11:45:26.371Z")
	s.Assert().NoError(err)

	// valid use case
	url, err = GetJobStatusCallbackURL("https://example.org", "1", ts)
	s.Assert().Equal("https://example.org/actions/build/1/jobs/{job_id}?timestamp=2014-11-12T11%3A45%3A26.371Z", url)
	s.Assert().NoError(err)

	// invalid base url
	url, err = GetJobStatusCallbackURL("this-is-not-a-url", "1", ts)
	s.Assert().Equal("", url)
	s.Assert().Error(err)

	// no zero time
	url, err = GetJobStatusCallbackURL("https://example.org", "1", time.Time{})
	s.Assert().Equal("", url)
	s.Assert().Error(err)

	// no empty workflow
	url, err = GetJobStatusCallbackURL("https://example.org", "", time.Time{})
	s.Assert().Equal("", url)
	s.Assert().Error(err)
}

func (s *receiverURLTestSuite) TestGetActionResolutionURL() {
	var url string
	var err error

	ts, err := time.Parse(time.RFC3339Nano, "2014-11-12T11:45:26.371Z")
	s.Assert().NoError(err)

	// valid use case
	url, err = GetActionResolutionURL("https://example.org", "1", ts)
	s.Assert().Equal("https://example.org/actions/build/1/jobs/{job_id}/resolve/actions?timestamp=2014-11-12T11%3A45%3A26.371Z", url)
	s.Assert().NoError(err)

	// invalid base url
	url, err = GetActionResolutionURL("this-is-not-a-url", "1", ts)
	s.Assert().Equal("", url)
	s.Assert().Error(err)

	// no zero time
	url, err = GetActionResolutionURL("https://example.org", "1", time.Time{})
	s.Assert().Equal("", url)
	s.Assert().Error(err)

	// no empty workflow
	url, err = GetActionResolutionURL("https://example.org", "", time.Time{})
	s.Assert().Equal("", url)
	s.Assert().Error(err)
}

func (s *receiverURLTestSuite) TestGetRunStatusCallbackURL() {
	var url string
	var err error

	ts, err := time.Parse(time.RFC3339Nano, "2014-11-12T11:45:26.371Z")
	s.Assert().NoError(err)

	// valid use case
	url, err = GetRunStatusCallbackURL("https://example.org", "1", ts)
	s.Assert().Equal("https://example.org/actions/build/1?timestamp=2014-11-12T11%3A45%3A26.371Z", url)
	s.Assert().NoError(err)
}
