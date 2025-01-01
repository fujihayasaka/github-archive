package engines

import (
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/internal/featureflag"
	"github.com/github/billing-platform/internal/monolith"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/interfaces"
	"go.opentelemetry.io/otel/trace"

	stats "github.com/github/go-stats"
)

type EngineParams struct {
	aqueductClient aqueduct.Client
	cfg            *config.Config
	db             interfaces.Database
	flagger        featureflag.FlagChecker
	statter        stats.Client
	tracer         trace.Tracer
	monolithClient *monolith.Client
}

func NewEngineParams(
	aqueductClient aqueduct.Client,
	cfg *config.Config,
	db interfaces.Database,
	flagger featureflag.FlagChecker,
	statter stats.Client,
	monolithClient *monolith.Client,
	tracer trace.Tracer,
) *EngineParams {
	return &EngineParams{
		aqueductClient: aqueductClient,
		cfg:            cfg,
		db:             db,
		flagger:        flagger,
		statter:        statter,
		monolithClient: monolithClient,
		tracer:         tracer,
	}
}
