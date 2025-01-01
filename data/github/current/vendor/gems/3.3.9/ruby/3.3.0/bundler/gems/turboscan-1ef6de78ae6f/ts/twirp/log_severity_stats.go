package twirp

import (
	"context"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	twirplog "github.com/github/go-twirp/v2/server/hooks/log"
	"github.com/github/turboscan/ts"
)

// this is an experiment to check the impact of moving the severity from the physical to the logical alert
// https://github.com/github/code-scanning/issues/6281
func logSeverityStats(ctx context.Context, la ts.LogicalAlert) {
	pa, err := la.Canonical()
	if err != nil {
		appctx.Stats(ctx).Counter("alert_severity_experiment", stats.Tags{"case": "no_canonical"}, 1)
		return
	}

	if la.SeverityLevel != pa.SeverityLevel || !equalSecuritySeverities(la.SecuritySeverity, pa.SecuritySeverity) {
		appctx.Stats(ctx).Counter("alert_severity_experiment", stats.Tags{"case": "mismatch"}, 1)
		appctx.Logger(ctx).WithFields(twirplog.DefaultFields(ctx)...).Info("Mismatched alert severity",
			kvp.Uint64("gh.turboscan.logical_alert_id", uint64(la.ID)),
			kvp.Uint64("gh.turboscan.physical_alert_id", uint64(pa.ID)),
			la.RepositoryID.AsKVP(),
			pa.RepositoryID.AsKVP(),
			kvp.String("gh.turboscan.logical_severity", la.SeverityLevel.String()),
			kvp.String("gh.turboscan.physical_severity", pa.SeverityLevel.String()),
			kvp.Float64p("gh.turboscan.logical_security_severity", la.SecuritySeverity),
			kvp.Float64p("gh.turboscan.physical_security_severity", pa.SecuritySeverity),
			kvp.Uint64("gh.turboscan.logical_alert_tool_id", uint64(la.Rule.ToolID)),
		)
		return
	}

	appctx.Stats(ctx).Counter("alert_severity_experiment", stats.Tags{"case": "match"}, 1)
}

func equalSecuritySeverities(a *float64, b *float64) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	return *a == *b
}
