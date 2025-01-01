package fields

// This is hand-written

import (
	"net/url"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	goerrors "github.com/go-errors/errors"
)

// headerToKey converts from HTTP header style (Content-Length) to semantic convention key style (content_length)
func headerToKey(headerName string) string {
	headerName = strings.ReplaceAll(headerName, "-", "_")
	headerName = strings.ToLower(headerName)
	return headerName
}

// RequestHeader appends an HTTP header name to a key prefix and uses that as the key for a kvp.Field
func (h *http) RequestHeader(headerName, value string) kvp.Field {
	return kvp.String("http.request.header."+headerToKey(headerName), value)
}

// ResponseHeader appends an HTTP header name to a key prefix and uses that as the key for a kvp.Field
func (h *http) ResponseHeader(headerName, value string) kvp.Field {
	return kvp.String("http.response.header."+headerToKey(headerName), value)
}

// NetListenAddress appends name to a key prefix and uses that as a key for a kvp.Field.
// address is either a URL or a "host:port" value that is sanitized and used as the value.
//
// name should only contain lower case letters and underscores, and describes the listen
// address in some human-understandable name: myservice_frontend, chatops_endpoint, etc.
//
// host may be an IP address or a domain name.
//
// If the host cannot be determined, the string "0.0.0.0" will be used for the host portion of the value.
// If the port cannot be determined, the string "invalid_port" will be used for the port portion of the value.
//
// http.Request.Addr is often what is passed in as the address parameter.
func (g gh) NetListenAddress(name, listenAddress string) kvp.Field {
	name = strings.ToLower(name)
	name = strings.ReplaceAll(name, "-", "_")
	name = strings.ReplaceAll(name, ".", "_")

	if !strings.Contains(listenAddress, "://") {
		listenAddress = "tcp://" + listenAddress
	}

	key := "gh.net.listen_address." + name
	listenURL, err := url.Parse(listenAddress)
	if err != nil {
		// If the URL doesn't parse, try adding "tcp://"
		listenURL, err = url.Parse("tcp://" + listenAddress)
		if err != nil {
			// Worst case, return what we were given.
			return kvp.String(key, listenAddress)
		}
	}

	// Fixup schema, host and port to reflect that port is required and host
	// defaults to 0.0.0.0 if not specified and schema defaults to tcp if not
	// specified.
	hostport := strings.SplitN(listenURL.Host, ":", 2)
	var host, port string
	if len(hostport) < 1 || hostport[0] == "" {
		host = "0.0.0.0"
	} else {
		host = hostport[0]
	}
	if len(hostport) < 2 || hostport[1] == "" {
		port = "invalid_port"
	} else {
		port = hostport[1]
	}
	listenURL.Host = host + ":" + port

	return kvp.String(key, listenURL.String())
}

// ExtractErrorFields provides a helper to extract fields from an error as provided by otel spec for keys
// the use case for this is around needles and traces vs just being isolated in WithError
func ExtractErrorFields(err error) []kvp.Field {
	f := make([]kvp.Field, 0)
	if err != nil {
		goerr := goerrors.New(err)
		f = append(f,
			Exception.Message(err.Error()),
			Exception.Stacktrace(string(goerr.Stack())),
			Exception.Type(goerr.TypeName()),
		)
	}
	return f
}
