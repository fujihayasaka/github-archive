package fault

import (
	"net/http"
)

const rejectFaultRoundTripperName = "rejectFaultRoundTripper"

type rejectFaultRoundTripper struct {
	reporter Reporter
	err      error
}

func NewRejectFault(reporter Reporter, err error) Injector {
	return &rejectFaultRoundTripper{
		reporter: reporter,
		err:      err,
	}
}

func (s *rejectFaultRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	s.reporter.Report(req.Context(), rejectFaultRoundTripperName, StateStarted)

	return nil, s.err
}

func (s *rejectFaultRoundTripper) chain(_ http.RoundTripper) Injector {
	return &rejectFaultRoundTripper{
		reporter: s.reporter,
		err:      s.err,
	}
}
