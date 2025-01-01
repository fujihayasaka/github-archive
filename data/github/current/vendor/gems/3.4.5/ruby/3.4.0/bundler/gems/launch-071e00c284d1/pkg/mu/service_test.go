package mu_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi"
	"github.com/stretchr/testify/assert"

	"github.com/github/launch/pkg/mu"
)

type testService struct {
	methods map[string]bool
}

func newTestService() *testService {
	return &testService{
		methods: make(map[string]bool),
	}
}

func (s *testService) ServiceContext(r *http.Request) {
}

func (s *testService) Routes() []mu.Route {
	return []mu.Route{
		mu.Delete("/", s.h),
		mu.Get("/", s.h),
		mu.Head("/", s.h),
		mu.Options("/", s.h),
		mu.Patch("/", s.h),
		mu.Post("/", s.h),
		mu.Put("/", s.h),
		mu.Trace("/", s.h),
	}
}

func (s *testService) h(w http.ResponseWriter, r *http.Request) {
	s.methods[r.Method] = true
}

func TestHTTPVerbRouting(t *testing.T) {
	r := chi.NewRouter()
	s := newTestService()
	mu.RouteService(r, s)

	ts := httptest.NewServer(r)
	defer ts.Close()

	methods := []string{
		"DELETE",
		"GET",
		"HEAD",
		"OPTIONS",
		"PATCH",
		"POST",
		"PUT",
		"TRACE",
	}

	for _, m := range methods {
		req, err := http.NewRequest(m, ts.URL, nil)
		if err != nil {
			t.Errorf("error creating request: %v", err)
		}

		_, err = http.DefaultClient.Do(req)
		if err != nil {
			t.Errorf("error doing request: % v", err)
		}

		if !s.methods[m] {
			t.Errorf("%s route not called", m)
		}
	}
}

type exApp struct{}

func (a *exApp) OnStartUp(*mu.Service) error {
	return nil
}

type healthApp struct {
	exApp
	status mu.HealthCheckStatus
	checks map[string]interface{}
}

type strHealthApp struct {
	exApp
	status string
	checks map[string]interface{}
}

// HealthStatus implements healthChecker interface
func (a *healthApp) OnHealthCheck(*mu.Service) (mu.HealthCheckStatus, map[string]interface{}) {
	return a.status, a.checks
}

// HealthStatus implements healthCheckerStr interface
func (a *strHealthApp) OnHealthCheck(*mu.Service) (string, map[string]interface{}) {
	return a.status, a.checks
}

func TestService_HealthStatus(t *testing.T) {
	t.Run("healthChecker", func(t *testing.T) {
		checks := map[string]interface{}{
			"foo": "bar",
		}
		svc := &mu.Service{
			Config: &mu.Config{
				Application: &healthApp{
					status: mu.HealthCheckOK,
					checks: checks,
				},
			},
		}
		gotStatus, gotChecks := svc.HealthStatus()
		assert.Equal(t, mu.HealthCheckOK, gotStatus)
		assert.Equal(t, checks, gotChecks)
	})

	t.Run("healthCheckerStr", func(t *testing.T) {
		checks := map[string]interface{}{
			"foo": "bar",
		}
		svc := &mu.Service{
			Config: &mu.Config{
				Application: &strHealthApp{
					status: "ERROR",
					checks: checks,
				},
			},
		}
		gotStatus, gotChecks := svc.HealthStatus()
		assert.Equal(t, mu.HealthCheckError, gotStatus)
		assert.Equal(t, checks, gotChecks)
	})

	t.Run("no health check", func(t *testing.T) {
		svc := &mu.Service{
			Config: &mu.Config{
				Application: &exApp{},
			},
		}
		gotStatus, gotChecks := svc.HealthStatus()
		assert.Equal(t, mu.HealthCheckOK, gotStatus)
		assert.Empty(t, gotChecks)
	})
}
