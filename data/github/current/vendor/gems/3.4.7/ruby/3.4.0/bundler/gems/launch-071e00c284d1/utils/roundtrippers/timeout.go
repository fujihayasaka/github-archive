package roundtrippers

import (
	"net/http"

	"github.com/CGA1123/shed"
)

func PropagateTimeout(next http.RoundTripper, opts ...shed.RoundTripperOpt) http.RoundTripper {
	// REVIEW:  should this method also set the standard Request-Timeout header?
	return shed.RoundTripper(next, opts...)
}
