package ts

import (
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"go.uber.org/zap/zapcore"
)

type PublishedEnabledStateID uint64

type EnablementReason uint32

// These int values are used in the database, so don't remove or re-number them.
// See column 'reason' in schemas/ts_published_enabled_states.sql
const (
	EnablementReason_ENABLE_DEFAULT_SETUP  = EnablementReason(1)
	EnablementReason_RECEIVED_ANALYSIS     = EnablementReason(2)
	EnablementReason_DISABLE_DEFAULT_SETUP = EnablementReason(3)
	EnablementReason_DELETED_ANALYSIS      = EnablementReason(4)
	EnablementReason_DEFAULT_BRANCH_CHANGE = EnablementReason(5)
	EnablementReason_OBSERVED_CHANGE       = EnablementReason(6)
)

func (r EnablementReason) String() string {
	switch r {
	case EnablementReason_ENABLE_DEFAULT_SETUP:
		return "ENABLE_DEFAULT_SETUP"
	case EnablementReason_RECEIVED_ANALYSIS:
		return "RECEIVED_ANALYSIS"
	case EnablementReason_DISABLE_DEFAULT_SETUP:
		return "DISABLE_DEFAULT_SETUP"
	case EnablementReason_DELETED_ANALYSIS:
		return "DELETED_ANALYSIS"
	case EnablementReason_DEFAULT_BRANCH_CHANGE:
		return "DEFAULT_BRANCH_CHANGE"
	case EnablementReason_OBSERVED_CHANGE:
		return "OBSERVED_CHANGE"
	default:
		return fmt.Sprintf("unknown reason %d", uint32(r))
	}
}

func (r EnablementReason) AsKVP() zapcore.Field {
	return kvp.String("gh.turboscan.enablement_reason", r.String())
}

type PublishedEnabledState struct {
	BaseModel
	ID           PublishedEnabledStateID
	RepositoryID RepositoryEID
	Enabled      bool
	Reason       EnablementReason
}
