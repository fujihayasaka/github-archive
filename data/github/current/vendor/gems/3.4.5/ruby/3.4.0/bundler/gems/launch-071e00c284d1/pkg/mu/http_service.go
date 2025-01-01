package mu

import (
	"net/http"
	"path"
	"reflect"
	"runtime"
	"strings"

	"github.com/go-chi/chi"
)

// httpServicer describes the interface for a mu HTTP service
type httpServicer interface {
	Routes() []Route
	ServiceContext(*http.Request)
}

// httpService routes http services on a mux
type httpService struct {
	mux    chi.Router
	routes []httpRoute
	server *httpServer
}

// newHTTPService ...
func newHTTPService(mux chi.Router, server *httpServer) *httpService {
	return &httpService{
		mux:    mux,
		server: server,
	}
}

func (s *httpService) Mount(svc httpServicer, middlewares ...func(http.Handler) http.Handler) {
	if s == nil {
		return
	}

	s.routes = append(s.routes, httpRoute{servicer: svc, middlewares: middlewares})
}

func (s *httpService) ServiceMap() serviceInfo {
	info := serviceInfo{
		Name:    "HTTP",
		Address: s.server.Address(),
	}

	for _, svcRoute := range s.routes {
		for _, route := range svcRoute.servicer.Routes() {

			name := runtime.FuncForPC(reflect.ValueOf(route.Handler).Pointer()).Name()
			funcName := strings.TrimSuffix(strings.TrimSuffix(path.Base(name), "-fm"), ")")

			info.Methods = append(info.Methods, serviceMethod{
				Name:   funcName,
				Method: route.Method,
				Route:  route.Path,
			})
		}
	}

	return info
}

// MountServices() (internal) mounts services on the service's mux in
// preparation for serving traffic.
func (s *httpService) MountServices() {
	for _, svc := range s.routes {
		servicer := svc.servicer
		for _, route := range servicer.Routes() {
			// This assembles the equivalent of:
			// rtr.With(s.ServiceContext).Get("/foo", barHandler)
			// Where the s.ServiceContext is wrapped in a middleware-aware
			// handler, and the appropriate chi method is used depending on
			// the Method of the Route.
			with := s.mux.With(svc.middlewares...)
			m := route.rtrMethod(with.With(ctxCaller(servicer)))
			m(route.Path, route.Handler)
		}
	}
}

type httpRoute struct {
	servicer    httpServicer
	middlewares []func(http.Handler) http.Handler
}

func ctxCaller(s Servicer) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			s.ServiceContext(r)
			next.ServeHTTP(w, r)
		})
	}
}
