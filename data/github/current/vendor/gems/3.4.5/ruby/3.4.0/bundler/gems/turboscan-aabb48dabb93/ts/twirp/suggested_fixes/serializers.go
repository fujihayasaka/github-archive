package suggested_fixes

import (
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func serializeSuggestedFixAlert(sfa ts.SuggestedFixAlert, outdated bool) *proto.SuggestedFixAlert {
	sfaProto := &proto.SuggestedFixAlert{
		AlertNumber:         sfa.LogicalAlertNumber,
		CreatedAt:           timestamppb.New(sfa.CreatedAt.Time),
		UpdatedAt:           timestamppb.New(sfa.UpdatedAt.Time),
		RuleSarifIdentifier: sfa.RuleSarifIdentifier,
		State:               serializeSuggestedFixAlertState(sfa.State),
	}

	sfaProto.StateUpdatedAt = timestamppb.New(sfa.StateUpdatedAt.Time)

	if sfa.StateUpdatedActorId != nil {
		sfaProto.StateUpdatedActorId = uint64(*sfa.StateUpdatedActorId)
	}

	if sfa.SuggestedFix != nil {
		sfaProto.SuggestedFix = serializeSuggestedFix(sfa.SuggestedFix)
		sfaProto.SuggestedFix.Outdated = outdated
	}

	return sfaProto
}

func serializeSuggestedFixAlertState(state ts.SuggestedFixAlertState) proto.SuggestedFixAlertState {
	switch state {
	case ts.SuggestedFixAlertStateApplied:
		return proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_APPLIED
	case ts.SuggestedFixAlertStateError:
		return proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_ERROR
	case ts.SuggestedFixAlertStateInvalid:
		return proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_INVALID
	case ts.SuggestedFixAlertStateRuleNotSupported:
		return proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED
	case ts.SuggestedFixAlertStatePending:
		return proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_PENDING
	case ts.SuggestedFixAlertStateValid:
		return proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_VALID
	case ts.SuggestedFixAlertStateValidMissingDep:
		return proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_VALID_MISSING_DEP
	default:
		return proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_UNKNOWN
	}
}

func serializeSuggestedFix(sf *ts.SuggestedFix) *proto.SuggestedFix {
	var files []*proto.SuggestedFixFile
	for _, f := range sf.Files {

		file := &proto.SuggestedFixFile{
			FilePath:    f.FilePath,
			DiffContent: f.FormatDiff(),
			CreatedAt:   timestamppb.New(f.CreatedAt.Time),
			UpdatedAt:   timestamppb.New(f.UpdatedAt.Time),
		}
		files = append(files, file)
	}

	sfProto := &proto.SuggestedFix{
		Files:       files,
		CreatedAt:   timestamppb.New(sf.CreatedAt.Time),
		UpdatedAt:   timestamppb.New(sf.UpdatedAt.Time),
		Description: sf.Description,
	}

	if sf.DependencyMetadata != nil {
		dependencyProto := make([]*proto.DependencyMetadata, len(sf.DependencyMetadata))

		for i, metadata := range sf.DependencyMetadata {
			dependencyProto[i] = &proto.DependencyMetadata{
				Name:        metadata.Name,
				Version:     metadata.Version,
				Url:         metadata.Url,
				Description: metadata.Description,
				Ecosystem:   metadata.Ecosystem,
				Malicious:   metadata.IsMalicious,
				Advisories:  make([]*proto.Advisory, len(metadata.Advisories)),
			}

			for j, advisory := range metadata.Advisories {
				dependencyProto[i].Advisories[j] = &proto.Advisory{
					Id:          advisory.Id,
					HtmlUrl:     advisory.HtmlUrl,
					Summary:     advisory.Summmary,
					Description: advisory.Description,
					Severity:    serializeAdvisorySeverity(advisory.Severity),
				}
			}
		}

		sfProto.DependencyMetadata = dependencyProto
	}

	return sfProto
}

func serializeAdvisorySeverity(severity ts.SuggestedFixAdvisorySeverity) proto.AdvisorySeverity {
	switch severity {
	case ts.SuggestedFixAdvisorySeverity_UNKNOWN:
		return proto.AdvisorySeverity_ADVISORY_SEVERITY_UNKNOWN
	case ts.SuggestedFixAdvisorySeverity_LOW:
		return proto.AdvisorySeverity_ADVISORY_SEVERITY_LOW
	case ts.SuggestedFixAdvisorySeverity_MEDIUM:
		return proto.AdvisorySeverity_ADVISORY_SEVERITY_MEDIUM
	case ts.SuggestedFixAdvisorySeverity_HIGH:
		return proto.AdvisorySeverity_ADVISORY_SEVERITY_HIGH
	case ts.SuggestedFixAdvisorySeverity_CRITICAL:
		return proto.AdvisorySeverity_ADVISORY_SEVERITY_CRITICAL
	default:
		return proto.AdvisorySeverity_ADVISORY_SEVERITY_UNKNOWN
	}
}
