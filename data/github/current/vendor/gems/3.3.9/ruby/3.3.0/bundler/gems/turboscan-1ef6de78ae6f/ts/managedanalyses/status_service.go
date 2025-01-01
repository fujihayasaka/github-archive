package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts"
)

// StatusService is used as an interface for enabled_status.EnabledStatusService
type StatusService interface {
	PublishStatusIfChanged(context.Context, ts.RepositoryEID, ts.EnablementReason, []byte, *bool)
	PublishStatusForDefaultSetup(ctx context.Context, repoID ts.RepositoryEID, reason ts.EnablementReason)
}
