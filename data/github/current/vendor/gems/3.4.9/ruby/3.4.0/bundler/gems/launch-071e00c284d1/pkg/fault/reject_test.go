package fault

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/require"
)

const (
	successRejectedText = "survived the rejected fault"
)

func Test_rejectFaultRoundTripper(t *testing.T) {
	tests := []struct {
		wantResp *http.Response
		wantErr  error
		name     string
	}{
		{
			name:     "rejects",
			wantResp: newResp(0, ""),
			wantErr:  io.EOF,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantErr == nil && tt.wantResp == nil {
				t.Errorf("must set either wantErr or wantResp")
				return
			}

			// Arrange
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				fmt.Fprintln(w, successRejectedText)
			}))
			defer ts.Close()
			tc := ts.Client()

			i := ChainInjectors(tc.Transport, NewRejectFault(NewNoopReporter(), tt.wantErr))
			s := NewFault(tc.Transport, i)
			tc.Transport = s

			// Act
			gotResp, gotErr := tc.Get(ts.URL)

			// Assert
			if tt.wantErr != nil {
				urlError, ok := extractHTTPErr(gotErr)
				if !ok {
					t.Errorf("error returned is not of type url.Error")
					return
				}
				require.Equal(t, tt.wantErr, urlError)
			} else {
				require.Equal(t, tt.wantResp.StatusCode, gotResp.StatusCode)
				require.Equal(t, extractBodyText(tt.wantResp), extractBodyText(gotResp))
			}
		})
	}
}
