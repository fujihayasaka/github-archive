package mu

import (
	"fmt"
	"net/http"
	"time"

	"github.com/github/launch/pkg/mu/muhttp/mw"
)

type pingService struct {
	buildVersion string
	muVersion    string
}

func newPingService(buildVersion, muVersion string) *pingService {
	return &pingService{
		buildVersion: buildVersion,
		muVersion:    muVersion,
	}
}

func (s *pingService) Routes() []Route {
	return []Route{
		Get("/_ping", s.ping),
	}
}

func (s *pingService) ServiceContext(req *http.Request) {
	mw.SkipLogging(req.Context())
}

func (s *pingService) ping(w http.ResponseWriter, _ *http.Request) {
	fmt.Fprintf(w, "OK - %s - %s - %s\n", // nolint: errcheck, gosec
		s.buildVersion,
		s.muVersion,
		time.Now().UTC())
}
