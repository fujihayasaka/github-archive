package stringutils

import (
	"bytes"
	"hash/fnv"
	"io"
	"net/http"
	"net/http/httputil"
)

// Used only for logging and debugging requests in test or lab environments.
func HTTPRequestToString(req *http.Request) (string, error) {
	// http.Request.Body is an io.ReadCloser, which can only be read once,
	// so save it to set it in the cloned request and reset the original request
	body, err := io.ReadAll(req.Body)
	if err != nil {
		return "", err
	}

	reqClone := req.Clone(req.Context())
	req.Body = io.NopCloser(bytes.NewReader(body))
	reqClone.Body = io.NopCloser(bytes.NewReader(body))

	// Do not include Authorization header
	reqClone.Header.Del("Authorization")

	dump, err := httputil.DumpRequest(reqClone, true)
	if err != nil {
		return "", err
	}

	return string(dump), nil
}

func Hash(s string) uint32 {
	h := fnv.New32a()
	h.Write([]byte(s))
	return h.Sum32()
}
