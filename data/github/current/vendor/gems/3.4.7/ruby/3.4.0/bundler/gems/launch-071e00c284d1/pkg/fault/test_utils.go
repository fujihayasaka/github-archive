package fault

import (
	"bytes"
	"errors"
	"io"
	"net/http"
	"net/url"
)

func newResp(code int, body string) *http.Response {
	if (code < http.StatusOK || code > http.StatusNetworkAuthenticationRequired) && body == "" {
		return nil
	}
	return &http.Response{
		StatusCode: code,
		Body:       io.NopCloser(bytes.NewBufferString(body)),
	}
}

//revive:disable-next-line:error-return
func extractHTTPErr(err error) (error, bool) {
	var urlErr *url.Error
	if ok := errors.As(err, &urlErr); ok {
		return urlErr.Err, ok
	}
	return nil, false
}

func extractBodyText(resp *http.Response) string {
	buf := new(bytes.Buffer)
	_, _ = buf.ReadFrom(resp.Body)
	return buf.String()
}
