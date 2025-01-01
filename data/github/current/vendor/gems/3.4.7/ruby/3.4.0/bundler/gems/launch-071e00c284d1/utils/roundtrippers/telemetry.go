package roundtrippers

import (
	"crypto/tls"
	"net/http"
	"net/http/httptrace"
	"time"
)

type Timings struct {
	Start             time.Time
	GetConn           time.Duration
	GotConn           time.Duration
	DNSStart          time.Duration
	DNSDone           time.Duration
	ConnectStart      time.Duration
	ConnectDone       time.Duration
	TLSHandShakeStart time.Duration
	TLSHandShakeDone  time.Duration
	WroteHeaders      time.Duration
	WroteRequest      time.Duration
	FirstResponseByte time.Duration
	TotalLatency      time.Duration
}

type Hook func(*http.Request, *http.Response, *Timings, error)

type telemetryRoundTripper struct {
	next  http.RoundTripper
	hooks []Hook
	now   func() time.Time
}

func NewTelemetryRoundTripper(next http.RoundTripper, hooks ...Hook) http.RoundTripper {
	return &telemetryRoundTripper{
		next:  next,
		hooks: hooks,
		now:   time.Now,
	}
}

func (trt *telemetryRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	timings := &Timings{}

	trace := &httptrace.ClientTrace{
		GetConn: func(string) {
			timings.GetConn = trt.now().Sub(timings.Start)
		},
		GotConn: func(httptrace.GotConnInfo) {
			timings.GotConn = trt.now().Sub(timings.Start)
		},
		DNSStart: func(httptrace.DNSStartInfo) {
			timings.DNSStart = trt.now().Sub(timings.Start)
		},
		DNSDone: func(httptrace.DNSDoneInfo) {
			timings.DNSDone = trt.now().Sub(timings.Start)
		},
		ConnectStart: func(network, addr string) {
			timings.ConnectStart = trt.now().Sub(timings.Start)
		},
		ConnectDone: func(string, string, error) {
			timings.ConnectDone = trt.now().Sub(timings.Start)
		},
		TLSHandshakeStart: func() {
			timings.TLSHandShakeStart = trt.now().Sub(timings.Start)
		},
		TLSHandshakeDone: func(tls.ConnectionState, error) {
			timings.TLSHandShakeDone = trt.now().Sub(timings.Start)
		},
		WroteHeaders: func() {
			timings.WroteHeaders = trt.now().Sub(timings.Start)
		},
		WroteRequest: func(_ httptrace.WroteRequestInfo) {
			timings.WroteRequest = trt.now().Sub(timings.Start)
		},
		GotFirstResponseByte: func() {
			timings.FirstResponseByte = trt.now().Sub(timings.Start)
		},
	}

	req = req.WithContext(httptrace.WithClientTrace(req.Context(), trace))
	timings.Start = trt.now()
	resp, err := trt.next.RoundTrip(req)
	timings.TotalLatency = trt.now().Sub(timings.Start)

	for _, hook := range trt.hooks {
		hook(req, resp, timings, err)
	}

	return resp, err
}
