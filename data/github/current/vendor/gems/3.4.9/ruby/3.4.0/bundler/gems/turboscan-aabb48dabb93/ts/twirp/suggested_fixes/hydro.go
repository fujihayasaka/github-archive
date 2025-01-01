package suggested_fixes

import (
	"context"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	tshydro_entities "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0/entities"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
)

func (s *Service) emitAutofixGenerateHydroEvents(
	ctx context.Context,
	repositoryId ts.RepositoryEID,
	alertNumbers []uint32,
	refNamesBytes [][]byte,
	source proto.SuggestedFixSource,
	pullRequestId ts.PullRequestEID,
	securityCampaignId uint64,
) error {
	eventCount := len(alertNumbers) * len(refNamesBytes)
	hydroMessages := make([]*tshydro.AutofixGenerateEvent, 0, eventCount)
	for _, refNameBytes := range refNamesBytes {
		for _, alertNumber := range alertNumbers {
			generateEventMessage := &tshydro.AutofixGenerateEvent{
				RepositoryId:       uint64(repositoryId),
				LogicalAlertNumber: alertNumber,
				AnalysisRef:        refNameBytes,
				Source:             convertGenerateSource(source),
				PullRequestId:      uint64(pullRequestId),
				SecurityCampaignId: securityCampaignId,
			}
			hydroMessages = append(hydroMessages, generateEventMessage)
		}
	}
	return s.sf.AutofixGeneratePublisher.AutofixGenerateEventBatch(ctx, hydroMessages)
}

func convertGenerateSource(protoSource proto.SuggestedFixSource) tshydro_entities.AutofixGenerateEventSource {
	switch protoSource {
	case proto.SuggestedFixSource_SUGGESTED_FIX_SOURCE_UNKNOWN:
		return tshydro_entities.AutofixGenerateEventSource_AUTOFIX_GENERATE_EVENT_SOURCE_UNKNOWN
	case proto.SuggestedFixSource_SUGGESTED_FIX_SOURCE_PR:
		return tshydro_entities.AutofixGenerateEventSource_AUTOFIX_GENERATE_EVENT_SOURCE_PR
	case proto.SuggestedFixSource_SUGGESTED_FIX_SOURCE_ONDEMAND:
		return tshydro_entities.AutofixGenerateEventSource_AUTOFIX_GENERATE_EVENT_SOURCE_ONDEMAND
	case proto.SuggestedFixSource_SUGGESTED_FIX_SOURCE_ONDEMAND_API:
		return tshydro_entities.AutofixGenerateEventSource_AUTOFIX_GENERATE_EVENT_SOURCE_ONDEMAND_API
	case proto.SuggestedFixSource_SUGGESTED_FIX_SOURCE_SECURITY_CAMPAIGN:
		return tshydro_entities.AutofixGenerateEventSource_AUTOFIX_GENERATE_EVENT_SOURCE_SECURITY_CAMPAIGN
	default:
		return tshydro_entities.AutofixGenerateEventSource_AUTOFIX_GENERATE_EVENT_SOURCE_UNKNOWN
	}
}
