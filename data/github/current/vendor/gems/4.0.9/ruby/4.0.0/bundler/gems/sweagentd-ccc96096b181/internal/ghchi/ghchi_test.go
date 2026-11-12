package ghchi

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/require"
)

func TestRoute(t *testing.T) {
	r := chi.NewRouter()

	var reportedRoute string
	// Apply a test middleware that invokes the Route function and stores for later test assertion
	r.Use(func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			reportedRoute = Route(r)
			next.ServeHTTP(w, r)
		})
	})

	r.Group(func(r chi.Router) {
		r.Get("/chat/{user_id}/threads", func(w http.ResponseWriter, r *http.Request) {
			require.Equal(t, "12345", chi.URLParam(r, "user_id"))
			require.Equal(t, "/chat/:user_id/threads", Route(r))
		})
	})
	r.Group(func(r chi.Router) {
		r.Get("/no/params", func(w http.ResponseWriter, r *http.Request) {
			require.Equal(t, "/no/params", Route(r))
		})
	})

	rr := httptest.NewRecorder()
	req, err := http.NewRequest(http.MethodGet, "/chat/12345/threads", http.NoBody)
	require.NoError(t, err)
	r.ServeHTTP(rr, req)
	require.Equal(t, "/chat/:user_id/threads", reportedRoute)
	require.Equal(t, http.StatusOK, rr.Result().StatusCode)

	req, err = http.NewRequest(http.MethodGet, "/no/params", http.NoBody)
	require.NoError(t, err)
	r.ServeHTTP(rr, req)
	require.Equal(t, "/no/params", reportedRoute)
	require.Equal(t, http.StatusOK, rr.Result().StatusCode)
}
