package fault

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestNewFault(t *testing.T) {
	tests := []struct {
		injectors []Injector
		options   []Option
		name      string
		wantErr   bool
		wantCode  int
		path      string
	}{
		{
			name: "slow reject",
			injectors: []Injector{
				NewSlowFault(NewNoopReporter(), 10*time.Millisecond, time.Sleep),
				NewRejectFault(NewNoopReporter(), io.EOF),
			},
			wantErr: true,
		},
		{
			name: "slow error",
			injectors: []Injector{
				NewSlowFault(NewNoopReporter(), 1*time.Second, time.Sleep),
				NewErrorFault(NewNoopReporter(), 401, ""),
			},
			wantCode: 401,
		},
		{
			name: "slow",
			injectors: []Injector{
				NewSlowFault(NewNoopReporter(), 1*time.Second, time.Sleep),
			},
			wantErr: false,
		},
		{
			name: "path allow - fault inject if path allowed",
			injectors: []Injector{
				NewErrorFault(NewNoopReporter(), 401, ""),
			},
			path:     "thisisokaytofault",
			options:  []Option{WithFilters([]string{"/thisisokaytofault"}, nil)},
			wantCode: 401,
		},
		{
			name: "path allow - do not fault inject if path not marked as allowed",
			injectors: []Injector{
				NewErrorFault(NewNoopReporter(), 401, ""),
			},
			path:     "thisisnotokaytofault",
			options:  []Option{WithFilters([]string{"/thisisokaytofault"}, nil)},
			wantCode: 200,
		},
		{
			name: "path block - does not fault inject if path blocked",
			injectors: []Injector{
				NewErrorFault(NewNoopReporter(), 401, ""),
			},
			path:     "thisisnotokaytofault",
			options:  []Option{WithFilters(nil, []string{"/thisisnotokaytofault"})},
			wantCode: 200,
		},
		{
			name: "path block - does fault inject if path not blocked",
			injectors: []Injector{
				NewErrorFault(NewNoopReporter(), 401, ""),
			},
			path:     "thisisokaytofault",
			options:  []Option{WithFilters(nil, []string{"/thisisnotokaytofault"})},
			wantCode: 401,
		},
		{
			name: "path block - does not fault inject if path not blocked and allow list exists without path",
			injectors: []Injector{
				NewErrorFault(NewNoopReporter(), 401, ""),
			},
			path:     "thisisalsonotokaytofault",
			options:  []Option{WithFilters([]string{"/thisisallthatsallowedtofault"}, []string{"/thisisnotokaytofault"})},
			wantCode: 200,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Arrange
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				fmt.Fprintln(w, "survived chained fault")
			}))
			defer ts.Close()
			tc := ts.Client()

			i := ChainInjectors(tc.Transport, tt.injectors...)
			fault := NewFault(tc.Transport, i, tt.options...)
			tc.Transport = fault

			// Act
			url := fmt.Sprintf("%s/%s", ts.URL, tt.path)
			resp, err := tc.Get(url)

			// Assert
			if tt.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}

			if tt.wantCode != 0 {
				require.Equal(t, tt.wantCode, resp.StatusCode)
			}

		})
	}
}
