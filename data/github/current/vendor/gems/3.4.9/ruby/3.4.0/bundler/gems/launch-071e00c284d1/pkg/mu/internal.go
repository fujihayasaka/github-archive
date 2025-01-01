package mu

import (
	"expvar"
	"fmt"
	"net/http"
	"net/http/pprof"
)

type serviceMapper interface {
	ServiceMap() serviceInfo
}

type internalService struct {
	health  http.HandlerFunc
	boom    http.HandlerFunc
	mappers []serviceMapper
}

func newInternalService(healthHandler, boomHandler http.HandlerFunc, mappers ...serviceMapper) *internalService {
	return &internalService{
		health:  healthHandler,
		boom:    boomHandler,
		mappers: mappers,
	}
}

func (s *internalService) Routes() []Route {
	return []Route{
		Get("/_health", s.health),
		Get("/_boom", s.boom),
		Get("/_debug/vars", expvar.Handler().ServeHTTP),
		Get("/_debug/pprof", pprof.Index),
		Get("/_debug/pprof/heap", pprof.Handler("heap").ServeHTTP),
		Get("/_debug/pprof/cmdline", pprof.Cmdline),
		Get("/_debug/pprof/mutex", pprof.Handler("mutex").ServeHTTP),
		Get("/_debug/pprof/block", pprof.Handler("block").ServeHTTP),
		Get("/_debug/pprof/threadcreate", pprof.Handler("threadcreate").ServeHTTP),
		Get("/_debug/pprof/profile", pprof.Profile),
		Get("/_debug/pprof/symbol", pprof.Symbol),
		Get("/_debug/pprof/trace", pprof.Trace),
		Get("/_debug/pprof/goroutine", pprof.Handler("goroutine").ServeHTTP),
		Get("/_debug/routes", s.ServiceMapHandler),
	}
}

func (s *internalService) ServiceContext(_ *http.Request) {
}

func (s *internalService) ServiceMapHandler(w http.ResponseWriter, _ *http.Request) {
	for _, mapper := range s.mappers {
		fmt.Fprintf(w, "%s\n", mapper.ServiceMap()) // nolint: errcheck, gosec
	}
}
