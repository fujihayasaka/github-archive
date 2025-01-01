package fault

import (
	"net/http"
	"time"
)

const slowFaultRoundTripperName = "slowFaultRoundTripper"

type slowFaultRoundTripper struct {
	next     http.RoundTripper
	reporter Reporter

	duration  time.Duration
	timeSleep func(t time.Duration)
}

func NewSlowFault(reporter Reporter, duration time.Duration, slowF func(t time.Duration)) Injector {
	if slowF == nil {
		slowF = time.Sleep
	}

	return &slowFaultRoundTripper{
		reporter:  reporter,
		timeSleep: slowF,
		duration:  duration,
	}
}

func (s *slowFaultRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	s.reporter.Report(req.Context(), slowFaultRoundTripperName, StateStarted)
	s.timeSleep(s.duration)
	s.reporter.Report(req.Context(), slowFaultRoundTripperName, StateFinished)

	return s.next.RoundTrip(req)
}

func (s *slowFaultRoundTripper) chain(rt http.RoundTripper) Injector {
	return &slowFaultRoundTripper{
		reporter:  s.reporter,
		duration:  s.duration,
		timeSleep: s.timeSleep,
		next:      rt,
	}
}
