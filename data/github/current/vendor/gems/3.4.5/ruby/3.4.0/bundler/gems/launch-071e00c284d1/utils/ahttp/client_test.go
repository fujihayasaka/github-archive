package ahttp_test

import (
	"bytes"
	"fmt"
	"io"
	"math"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	circuit "github.com/rubyist/circuitbreaker"
	"github.com/stretchr/testify/assert"

	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/utils/mathutils"
	"github.com/github/launch/utils/timeutils"
)

func newClient(breaker *circuit.Breaker) *ahttp.Client {
	return ahttp.NewClient(breaker, statter.NullStatter(), ahttp.DefaultBackoffStrategy, apphttp.NewClient(), "test")
}

func assertDurationAbout(t *testing.T, a, b time.Time, durationSecs int) {
	t.Helper()
	actual := int(math.Floor(float64(a.Sub(b).Seconds())))
	if actual != durationSecs {
		t.Fatalf("expected %d secs, got %d", durationSecs, actual)
	}
}

func TestDo(t *testing.T) {
	m := http.NewServeMux()

	m.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "OK") // nolint: errcheck, gosec
	})
	s := httptest.NewServer(m)

	defer s.Close()

	breaker := circuit.NewThresholdBreaker(10)
	client := newClient(breaker)

	req, _ := http.NewRequest("GET", s.URL, nil)

	resp, err := client.Do(req)

	if err != nil {
		t.Error("expected err to be nil")
	}

	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected 200, got %d", resp.StatusCode)
	}

	if breaker.Successes() != 1 {
		t.Errorf("expected 1 success, got %d", breaker.Successes())
	}
}

func TestDoNoBreaker(t *testing.T) {
	m := http.NewServeMux()

	m.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "OK") // nolint: errcheck, gosec
	})
	s := httptest.NewServer(m)

	defer s.Close()

	client := newClient(nil)
	req, _ := http.NewRequest("GET", s.URL, nil)

	resp, err := client.Do(req)

	if err != nil {
		t.Error("expected err to be nil")
	}

	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected 200, got %d", resp.StatusCode)
	}
}

func TestDoWithFailure(t *testing.T) {
	m := http.NewServeMux()

	m.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	})
	s := httptest.NewServer(m)

	defer s.Close()

	breaker := circuit.NewThresholdBreaker(10)
	client := newClient(breaker)

	req, _ := http.NewRequest("GET", s.URL, nil)

	resp, err := client.Do(req)

	if err != nil {
		t.Error("expected err to be nil")
	}

	if resp.StatusCode != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", resp.StatusCode)
	}

	if f := breaker.Failures(); f != 1 {
		t.Errorf("expected 1 success, got %d", f)
	}
}

func TestDoWithOpenBreaker(t *testing.T) {
	breaker := circuit.NewThresholdBreaker(1)
	breaker.Break()

	client := newClient(breaker)
	client.RetryInterval = 2 * time.Second

	req, _ := http.NewRequest("GET", "http://example.com", nil)

	resp, err := client.Do(req)

	if resp != nil {
		t.Error("expected resp to be nil")
	}

	if err != circuit.ErrBreakerOpen {
		t.Error("expected error to be ErrBreakerOpen")
	}
}

func TestDoWithRetries(t *testing.T) {
	t.Parallel()

	var retryTimes []time.Time

	m := http.NewServeMux()

	m.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		retryTimes = append(retryTimes, time.Now())
		if len(retryTimes) == 3 {
			fmt.Fprintf(w, "OK") // nolint: errcheck, gosec
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
	})
	s := httptest.NewServer(m)

	defer s.Close()

	breaker := circuit.NewThresholdBreaker(10)
	client := newClient(breaker)
	client.RetryInterval = 2 * time.Second
	client.BackoffStrategy = constantBackoff

	req, _ := http.NewRequest("GET", s.URL, nil)

	resp, err := client.DoWithRetries(req)

	if err != nil {
		t.Error("expected err to be nil")
	}

	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected 200, got %d", resp.StatusCode)
	}

	if len(retryTimes) != 3 {
		t.Errorf("expected 3, got %d", len(retryTimes))
	}

	if s := breaker.Successes(); s != 1 {
		t.Errorf("expected 1 success, got %d", s)
	}

	assertDurationAbout(t, retryTimes[1], retryTimes[0], 2)
	assertDurationAbout(t, retryTimes[2], retryTimes[1], 2)
}

func TestDoWithLinearRetries(t *testing.T) {
	t.Parallel()

	var retryTimes []time.Time

	m := http.NewServeMux()

	m.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		retryTimes = append(retryTimes, time.Now())
		if len(retryTimes) == 3 {
			fmt.Fprintf(w, "OK") // nolint: errcheck, gosec
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
	})
	s := httptest.NewServer(m)

	defer s.Close()

	breaker := circuit.NewThresholdBreaker(10)
	client := newClient(breaker)
	client.RetryInterval = 1 * time.Second
	client.BackoffStrategy = linearBackoff

	req, _ := http.NewRequest("GET", s.URL, nil)

	resp, err := client.DoWithRetries(req)

	if err != nil {
		t.Error("expected err to be nil")
	}

	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected 200, got %d", resp.StatusCode)
	}

	if len(retryTimes) != 3 {
		t.Errorf("expected 3, got %d", len(retryTimes))
	}

	if s := breaker.Successes(); s != 1 {
		t.Errorf("expected 1 success, got %d", s)
	}

	assertDurationAbout(t, retryTimes[1], retryTimes[0], 1)
	assertDurationAbout(t, retryTimes[2], retryTimes[1], 2)
}

func TestDoWithExponentialRetries(t *testing.T) {
	t.Parallel()

	var retryTimes []time.Time

	m := http.NewServeMux()

	m.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		retryTimes = append(retryTimes, time.Now())
		if len(retryTimes) == 3 {
			fmt.Fprintf(w, "OK") // nolint: errcheck, gosec
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
	})
	s := httptest.NewServer(m)

	defer s.Close()

	breaker := circuit.NewThresholdBreaker(10)
	client := newClient(breaker)
	client.RetryInterval = 1 * time.Second
	client.BackoffStrategy = exponentialBackoff

	req, _ := http.NewRequest("GET", s.URL, nil)

	resp, err := client.DoWithRetries(req)

	if err != nil {
		t.Error("expected err to be nil")
	}

	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected 200, got %d", resp.StatusCode)
	}

	if len(retryTimes) != 3 {
		t.Errorf("expected 3, got %d", len(retryTimes))
	}

	if s := breaker.Successes(); s != 1 {
		t.Errorf("expected 1 success, got %d", s)
	}

	assertDurationAbout(t, retryTimes[1], retryTimes[0], 2)
	assertDurationAbout(t, retryTimes[2], retryTimes[1], 4)
}

func TestDoWithRetriesMaxFailures(t *testing.T) {
	requests := int64(0)

	m := http.NewServeMux()

	m.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt64(&requests, 1)
		w.WriteHeader(http.StatusInternalServerError)
	})
	s := httptest.NewServer(m)

	defer s.Close()

	breaker := circuit.NewThresholdBreaker(10)
	client := newClient(breaker)
	client.BackoffStrategy = constantBackoff

	req, _ := http.NewRequest("GET", s.URL, nil)

	resp, err := client.DoWithRetries(req)

	if err == nil {
		t.Error("expected err to not be nil")
	}

	if resp.StatusCode != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", resp.StatusCode)
	}

	if r := atomic.LoadInt64(&requests); r != 3 {
		t.Errorf("expected 3 requests, got %d", r)
	}

	if f := breaker.Failures(); f != 3 {
		t.Errorf("expected 3 failures, got %d", f)
	}
}

func TestDoWithRetriesWithOpenBreaker(t *testing.T) {
	breaker := circuit.NewThresholdBreaker(1)
	breaker.Break()

	client := newClient(breaker)

	req, _ := http.NewRequest("GET", "http://example.com", nil)

	resp, err := client.DoWithRetries(req)

	if resp != nil {
		t.Error("expected resp to be nil")
	}

	if err != circuit.ErrBreakerOpen {
		t.Error("expected error to be circuit.ErrBreakerOpen")
	}
}

func TestDoWithRetriesMaintainsPayload(t *testing.T) {
	requests := int64(0)

	m := http.NewServeMux()

	m.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		v := atomic.AddInt64(&requests, 1)
		if v == 3 {
			buf, err := io.ReadAll(r.Body)
			if err != nil {
				t.Error("expected err to be nil")
			}
			if string(buf) != `{"payload":true}` {
				t.Error("invalid json")
			}
			fmt.Fprintf(w, "OK") // nolint: errcheck, gosec
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
	})
	s := httptest.NewServer(m)

	defer s.Close()

	breaker := circuit.NewThresholdBreaker(10)
	client := newClient(breaker)

	req, _ := http.NewRequest("POST", s.URL, bytes.NewReader([]byte(`{"payload":true}`)))

	resp, err := client.DoWithRetries(req)

	if err != nil {
		t.Error("expected err to be nil")
	}

	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected 200, got %d", http.StatusOK)
	}

	if r := atomic.LoadInt64(&requests); r != 3 {
		t.Errorf("expected 3 requests, got %d", r)
	}

	if s := breaker.Successes(); s != 1 {
		t.Errorf("expected 1 success, got %d", s)
	}
}

func TestDoWithRetriesWithDataErrorRead(t *testing.T) {
	requests := int64(0)

	m := http.NewServeMux()

	m.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		v := atomic.AddInt64(&requests, 1)
		if v == 3 {
			buf, err := io.ReadAll(r.Body)
			if err != nil {
				t.Error("expected err to be nil")
			}

			if string(buf) != `{"payload":true}` {
				t.Error("invalid json")
			}
			fmt.Fprintf(w, "OK")
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
	})
	s := httptest.NewServer(m)

	defer s.Close()

	breaker := circuit.NewThresholdBreaker(10)
	client := newClient(breaker)

	req, _ := http.NewRequest("POST", s.URL, &errorReader{})

	_, err := client.DoWithRetries(req)

	if err == nil {
		t.Error("expected error to not be nil")
	}
}

func TestDoWithRetriesMaxFailuresReturnsError(t *testing.T) {
	breaker := circuit.NewThresholdBreaker(10)
	client := newClient(breaker)

	req, _ := http.NewRequest("GET", "http://localhost:82351", nil)

	_, err := client.DoWithRetries(req)

	if err == nil {
		t.Error("expected error to not be nil")
	}
}

type errorReader struct{}

func (*errorReader) Read([]byte) (int, error) {
	return 0, io.ErrClosedPipe
}

func TestDefaultBackoff(t *testing.T) {
	r := mathutils.NewSynchronizedRandProvider(rand.New(rand.NewSource(42)))
	backoffStrategy := ahttp.RandomizedExponentialBackoff(r, 0.0)
	c := ahttp.NewClient(nil, nil, backoffStrategy, nil, "none")
	expectedScale := 0
	for i := uint(0); i < 10; i++ {
		expected := timeutils.ScaleDuration(expectedScale, c.RetryInterval)
		assert.Equal(t, expected, c.BackoffStrategy(i, c.RetryInterval), "zero-based attempt=%d", i)
		expectedScale = max(1, 2*expectedScale)
	}
}

func TestRandomizedExponentialBackoff_WithNoJitter(t *testing.T) {

	retryBaseInterval := 1 * time.Millisecond

	r := mathutils.NewSynchronizedRandProvider(rand.New(rand.NewSource(42)))
	backoff := ahttp.RandomizedExponentialBackoff(r, 0.0)

	wantMilliseconds := []int64{
		0,
		1,
		2,
		4,
		8,
		16,
		32,
		64,
		128,
		256,
		512,
	}

	for i, expectedMillis := range wantMilliseconds {
		gotBackoff := backoff(uint(i), retryBaseInterval).Truncate(time.Millisecond)
		wantBackoff := timeutils.ScaleDuration(expectedMillis, time.Millisecond)
		assert.Equal(t, wantBackoff, gotBackoff, "zero-based attempt=%d", i)
	}
}

func TestRandomizedExponentialBackoff_WithPredictableJitter(t *testing.T) {

	retryBaseInterval := 1 * time.Second

	// 0.75 is 7/8ths of the distance within the interval [-1.0, 1.0],
	// so create a fake random number generator that always returns 7/8ths (0.875).
	expectedJitterScale := 0.75
	parrotValue := 0.875
	constantGenerator := mathutils.NewSynchronizedRandProvider(newConstantGenerator(0, parrotValue))
	backoff := ahttp.RandomizedExponentialBackoff(constantGenerator, 1.0)

	natural_backoff_millis := []float64{
		0_000,
		1_000,
		2_000,
		4_000,
		8_000,
		16_000,
		32_000,
		64_000,
		128_000,
		256_000,
		512_000,
	}

	for i, nb := range natural_backoff_millis {
		gotBackoff := backoff(uint(i), retryBaseInterval).Truncate(time.Millisecond)
		// recall that the formula for expected jitter in this case is:
		//   expected_jitter = natural_backoff + (j * natural_backoff)
		j := expectedJitterScale
		wantBackoff := timeutils.ScaleDuration(nb+(j*nb), time.Millisecond)
		assert.Equal(t, wantBackoff, gotBackoff, "zero-based attempt=%d", i)
	}
}

func TestRandomizedExponentialBackoff_WithRandomJitter(t *testing.T) {

	retryBaseInterval := 25 * time.Millisecond

	r := mathutils.NewSynchronizedRandProvider(rand.New(rand.NewSource(42)))
	backoff := ahttp.RandomizedExponentialBackoff(r, 0.25)

	wantMilliseconds := []int64{
		0,
		23,
		39,
		105,
		170,
		308,
		753,
		1850,
		3015,
		6025,
		13736,
	}

	for i, expectedMillis := range wantMilliseconds {
		gotBackoff := backoff(uint(i), retryBaseInterval).Truncate(time.Millisecond)
		wantBackoff := timeutils.ScaleDuration(expectedMillis, time.Millisecond)
		assert.Equal(t, wantBackoff, gotBackoff, "zero-based attempt=%d", i)
	}

}

// These backoff strategies have been ported from muhttp.Client to maintain the behavior in
// tests. Production code should use RandomizedExponentialBackoff instead.
// https://github.com/github/mu-actions/blob/62263ca51d2125a174bfbe26a6447b85db91794d/muhttp/client.go#L54-L67

// constantBackoff always returns a constant rate backoff attempt
func constantBackoff(_ uint, retryInterval time.Duration) time.Duration {
	return retryInterval
}

// linearBackoff returns increasing durations, each a retryInterval longer than the last
func linearBackoff(retryCount uint, retryInterval time.Duration) time.Duration {
	return time.Duration(retryCount) * retryInterval
}

// exponentialBackoff returns ever increasing backoffs by a power of 2
func exponentialBackoff(retryCount uint, retryInterval time.Duration) time.Duration {
	return time.Duration(1<<uint(retryCount)) * retryInterval
}

// implement our own, custom RandProvider as a way to generate predictable (constant) "random" values.
type constantGenerator struct {
	i int64
	f float64
}

func (cg *constantGenerator) Int63n(n int64) int64 {
	return min(cg.i, n)
}

func (cg *constantGenerator) Float64() float64 {
	return cg.f
}

func newConstantGenerator(constantInt int64, constantFloat float64) mathutils.RandProvider {
	return &constantGenerator{i: constantInt, f: constantFloat}
}
