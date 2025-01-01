// Package server contains Twirp server utilities and request hooks.
package server

import "net/http"

// PackageNameLabel is the tag used to identify the package name.
const PackageNameLabel = "twirp_package"

// ServiceNameLabel is the tag used to identify the service name.
const ServiceNameLabel = "twirp_service"

// MethodNameLabel is the tag used to identify the method name.
const MethodNameLabel = "twirp_method"

// StatusCodeLabel is the tag used to identify the status code.
const StatusCodeLabel = "twirp_status"

// TwirpServer is a subset of the generated twirp.Server interface that can be used for general
// purpose code.
type TwirpServer interface {
	http.Handler

	PathPrefix() string
}

// Register will add the supplied set of TwirpServers to the given http.ServeMux.
func Register(mux *http.ServeMux, twirpServices ...TwirpServer) {
	for _, service := range twirpServices {
		mux.Handle(service.PathPrefix(), service)
	}
}
