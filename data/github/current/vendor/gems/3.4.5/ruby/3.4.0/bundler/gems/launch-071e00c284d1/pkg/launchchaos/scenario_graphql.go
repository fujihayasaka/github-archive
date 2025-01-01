package launchchaos

import (
	"net/http"
	"time"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/fault"
)

const GraphQLSlowError = "graphql_slow_error"

func NewGraphQLSlowError(next http.RoundTripper, log logger.Logger, participator fault.Participator) http.RoundTripper {
	path := "/graphql"
	reporter := NewLogReporter(log)
	slowFault := fault.NewSlowFault(reporter, 3*time.Second, time.Sleep)
	errorFault := fault.NewErrorFault(reporter, 403, "Integration forbidden")
	chained := fault.ChainInjectors(next, slowFault, errorFault)
	return fault.NewFault(next, chained,
		fault.WithFilters([]string{path}, nil),
		fault.WithParticipator(participator),
	)
}
