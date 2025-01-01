package fault

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/require"
)

const (
	successErroredText = "survived the errored fault"
)

func Test_errorFaultRoundTripper(t *testing.T) {
	tests := []struct {
		name     string
		wantCode int
		wantText string
	}{
		{
			wantCode: 401,
			wantText: "unauthorized",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Arrange
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				fmt.Fprintln(w, successRejectedText)
			}))
			defer ts.Close()
			tc := ts.Client()

			i := ChainInjectors(tc.Transport, NewErrorFault(NewNoopReporter(), tt.wantCode, tt.wantText))
			s := NewFault(tc.Transport, i)
			tc.Transport = s

			// Act
			gotResp, err := tc.Get(ts.URL)

			// Assert
			require.NoError(t, err)
			require.Equal(t, tt.wantCode, gotResp.StatusCode)
			require.Equal(t, tt.wantText, extractBodyText(gotResp))
		})
	}
}
