package mu

import (
	"net/http"

	"github.com/go-chi/chi"
)

// Route maps an HTTP verb and path to a handler function.
type Route struct {
	Method  string           // HTTP Method to be used
	Path    string           // Route path (using chi's format)
	Handler http.HandlerFunc // HTTP Handler
}

// Connect wraps a handler for an HTTP CONNECT
func Connect(path string, h http.HandlerFunc) Route {
	return newRoute(sConnect, path, h)
}

// Get wraps a handler for an HTTP GET.
func Get(path string, h http.HandlerFunc) Route {
	return newRoute(sGet, path, h)
}

// Delete wraps a handler for an HTTP DELETE.
func Delete(path string, h http.HandlerFunc) Route {
	return newRoute(sDelete, path, h)
}

// Head wraps a handler for an HTTP HEAD.
func Head(path string, h http.HandlerFunc) Route {
	return newRoute(sHead, path, h)
}

// Options wraps a handler for an HTTP OPTIONS.
func Options(path string, h http.HandlerFunc) Route {
	return newRoute(sOptions, path, h)
}

// Patch wraps a handler for an HTTP PATCH.
func Patch(path string, h http.HandlerFunc) Route {
	return newRoute(sPatch, path, h)
}

// Post wraps a handler for an HTTP POST.
func Post(path string, h http.HandlerFunc) Route {
	return newRoute(sPost, path, h)
}

// Put wraps a handler for an HTTP PUT.
func Put(path string, h http.HandlerFunc) Route {
	return newRoute(sPut, path, h)
}

// Trace wraps a handler for an HTTP TRACE.
func Trace(path string, h http.HandlerFunc) Route {
	return newRoute(sTrace, path, h)
}

func newRoute(method, path string, h http.HandlerFunc) Route {
	return Route{
		Method:  method,
		Path:    path,
		Handler: h,
	}
}

func (r Route) rtrMethod(rtr chi.Router) func(string, http.HandlerFunc) {
	switch r.Method {
	case sConnect:
		return rtr.Connect
	case sGet:
		return rtr.Get
	case sDelete:
		return rtr.Delete
	case sHead:
		return rtr.Head
	case sOptions:
		return rtr.Options
	case sPatch:
		return rtr.Patch
	case sPost:
		return rtr.Post
	case sPut:
		return rtr.Put
	case sTrace:
		return rtr.Trace
	default:
		return rtr.HandleFunc
	}
}

const (
	sConnect = "CONNECT"
	sGet     = "GET"
	sDelete  = "DELETE"
	sHead    = "HEAD"
	sOptions = "OPTIONS"
	sPatch   = "PATCH"
	sPost    = "POST"
	sPut     = "PUT"
	sTrace   = "TRACE"
)
