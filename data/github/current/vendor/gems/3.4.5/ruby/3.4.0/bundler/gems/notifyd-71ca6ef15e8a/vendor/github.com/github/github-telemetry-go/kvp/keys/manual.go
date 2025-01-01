// THIS IS HAND-WRITTEN CODE!
//
// It needs to co-exist with the generated code, and look as similar as possible to it so users can use it intuitively
package keys

type prefix struct {
	// HttpRequestHeader is the prefix string "http.request.header." for constructing a key out of an HTTP request header
	HttpRequestHeader string
	// HttpResponseHeader is the prefix string "http.response.header." for constructing a key out of an HTTP response header
	HttpResponseHeader string
	// GhNetListenAddress is the prefix string "gh.net.listen_address." for constructing a key for a listen address (host:port listening on some interface)
	GhNetListenAddress string
}

// Prefix containes prefix values for keys that need to be constructed dynamically, not defined in yaml
var Prefix = prefix{
	HttpRequestHeader:  "http.request.header.",
	HttpResponseHeader: "http.response.header.",
	GhNetListenAddress: "gh.net.listen_address.",
}
