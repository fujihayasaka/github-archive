package fault

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func Test_slowFaultRoundTripper(t *testing.T) {
	tests := []struct {
		duration time.Duration
		name     string
	}{
		{
			name:     "sleep for a while",
			duration: 5 * time.Hour,
		},
		{
			name:     "sleep for no time at all",
			duration: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {

			// Arrange
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
			defer ts.Close()
			tc := ts.Client()

			start := time.Date(2022, time.March, 1, 1, 1, 1, 1, time.UTC)
			now := start
			timeSleep := func(d time.Duration) {
				now = now.Add(d)
			}

			i := ChainInjectors(tc.Transport, NewSlowFault(NewNoopReporter(), tt.duration, timeSleep))
			f := NewFault(tc.Transport, i)
			tc.Transport = f

			// Act
			_, err := tc.Get(ts.URL)

			// Assert
			if err != nil {
				t.Error(err)
				return
			}

			require.Equal(t, start.Add(tt.duration), now)
		})
	}
}
