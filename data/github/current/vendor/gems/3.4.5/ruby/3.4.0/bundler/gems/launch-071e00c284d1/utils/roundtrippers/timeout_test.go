package roundtrippers_test

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/CGA1123/shed"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/utils/roundtrippers"
)

type roundTripper func(r *http.Request) (*http.Response, error)

func (rt roundTripper) RoundTrip(r *http.Request) (*http.Response, error) {
	return rt(r)
}

func constantUntil(d time.Duration) func(time.Time) time.Duration {
	return func(time.Time) time.Duration {
		return d
	}
}

func Test_PropagateTimeout(t *testing.T) {
	cases := []struct {
		description    string
		headerTimeout  time.Duration
		contextTimeout time.Duration
		expectedHeader string
	}{
		{description: "With no timeout", expectedHeader: ""},
		{description: "With negative header timeout", headerTimeout: -time.Duration(1), expectedHeader: ""},
		{description: "With positive header timeout", headerTimeout: time.Second, expectedHeader: "1000"},
		{description: "With negative context timeout", contextTimeout: -time.Duration(1), expectedHeader: ""},
		{description: "With positive context timeout", contextTimeout: time.Second, expectedHeader: "1000"},
		{description: "With header timeout longer than context timeout", headerTimeout: time.Minute, contextTimeout: time.Second, expectedHeader: "1000"},
		{description: "With context timeout longer than header timeout", headerTimeout: time.Second, contextTimeout: time.Minute, expectedHeader: "1000"},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.description, func(t *testing.T) {
			t.Parallel()

			fakeRoundTripper := roundTripper(func(r *http.Request) (*http.Response, error) {
				assert.Equal(t, tc.expectedHeader, r.Header.Get("X-Client-Timeout-Ms"))

				resp := "ok\n"
				return &http.Response{
					Status:        "200 OK",
					StatusCode:    200,
					Proto:         "HTTP/1.1",
					ProtoMajor:    1,
					ProtoMinor:    1,
					Body:          io.NopCloser(bytes.NewBufferString(resp)),
					ContentLength: int64(len(resp)),
					Request:       r,
					Header:        make(http.Header),
				}, nil
			})

			opts := []shed.RoundTripperOpt{shed.WithMaxTimeout(tc.headerTimeout)}

			ctx := context.Background()
			if tc.contextTimeout != time.Duration(0) {
				timeoutCtx, cancel := context.WithTimeout(ctx, tc.contextTimeout)
				defer cancel()

				opts = append(opts, shed.WithUntilFunc(constantUntil(tc.contextTimeout)))
				ctx = timeoutCtx
			}

			rt := roundtrippers.PropagateTimeout(fakeRoundTripper, opts...)

			r, err := http.NewRequestWithContext(ctx, "GET", "/foo", nil)
			require.NoError(t, err)

			res, err := rt.RoundTrip(r)
			require.NoError(t, err)
			require.NoError(t, res.Body.Close())
		})
	}

}
