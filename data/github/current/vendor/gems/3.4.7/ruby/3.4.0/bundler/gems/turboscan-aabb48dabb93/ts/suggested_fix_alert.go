package ts

import (
	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"go.uber.org/zap/zapcore"
)

type SuggestedFixAlertID uint64

type SuggestedFixAlert struct {
	BaseModel
	ID                  SuggestedFixAlertID
	LogicalAlertNumber  uint32
	SuggestedFixID      *SuggestedFixID
	RepositoryID        RepositoryEID
	State               SuggestedFixAlertState
	StateUpdatedAt      sqltime.Time
	StateUpdatedActorId *UserEID
	RefBytes            []byte
	RuleSarifIdentifier string
	SuggestionUsage     *float64 // The proportion of our suggestion present in the actual fix (NULL if the alert is not fixed, 1.0 = our suggestion was used without changes, 0.0 = the fix is totally different from our suggestion)
	RequestedAt         sqltime.Time

	// association
	SuggestedFix *SuggestedFix

	// virtual, used by cocofix runner
	PhysicalAlert *PhysicalAlert `gorm:"-" verify:"ignore"`
}

func (sfa *SuggestedFixAlert) SetState(state SuggestedFixAlertState, actorId *UserEID) {
	sfa.State = state
	updatedAt := sqltime.Now()
	sfa.StateUpdatedAt = updatedAt

	if actorId != nil {
		sfa.StateUpdatedActorId = actorId
	}
}

func (sfa *SuggestedFixAlert) WasSuggestionUsed() bool {
	if sfa.SuggestionUsage == nil {
		return false
	}

	const SuggestionUsageThreshold = 0.5
	return *sfa.SuggestionUsage > SuggestionUsageThreshold
}

func (id SuggestedFixAlertID) AsKVP() zapcore.Field {
	return kvp.Uint64("gh.turboscan.suggested_fix_alert_id", uint64(id))
}
