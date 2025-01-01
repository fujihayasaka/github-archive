package tstypes

import (
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func CreateSearchByOrgsFilter(ownerIds []uint64, repositoryIds []uint64, repositoryIdsToExclude []uint64, filter *proto.AlertsFilter) (*ts.SearchByOrgsFilter, error) {
	out := &ts.SearchByOrgsFilter{}

	if len(ownerIds) > 0 {
		out.OwnerIDs = make([]ts.OwnerEID, len(ownerIds))
		for i, id := range ownerIds {
			if id == 0 {
				return nil, twerrors.InvalidArgumentError("owner_ids", "must be provided with values > 0")
			}
			out.OwnerIDs[i] = ts.OwnerEID(id)
		}
	}

	if len(repositoryIds) > 0 {
		out.RepositoryIDs = make([]ts.RepositoryEID, len(repositoryIds))
		for i, id := range repositoryIds {
			if id == 0 {
				return nil, twerrors.InvalidArgumentError("repository_id", "must be > 0")
			}
			out.RepositoryIDs[i] = ts.RepositoryEID(id)
		}
	}

	if len(repositoryIdsToExclude) > 0 {
		out.ExcludedRepositoryIDs = make([]ts.RepositoryEID, len(repositoryIdsToExclude))
		for i, id := range repositoryIdsToExclude {
			if id == 0 {
				return nil, twerrors.InvalidArgumentError("excluded_repository_id", "must be > 0")
			}
			out.ExcludedRepositoryIDs[i] = ts.RepositoryEID(id)
		}
	}

	if filter != nil {
		if len(filter.RepositoryVisibilities) > 0 {
			out.RepositoryVisibilities = make([]string, len(filter.RepositoryVisibilities))
			for i, visibility := range filter.RepositoryVisibilities {
				visibility, err := RepositoryVisibilityFilterFromProto(visibility)
				if err == nil {
					out.RepositoryVisibilities[i] = visibility
				} else {
					return nil, twerrors.InvalidArgumentError("repository_visibility", err.Error())
				}
			}
		}

		resolutions, err := ResolutionsFilterFromProto(filter.Resolutions)
		if err != nil {
			return nil, twerrors.InvalidArgumentError("resolutions", "")
		}

		excludedResolutions, err := ResolutionsFilterFromProto(filter.ExcludedResolutions)
		if err != nil {
			return nil, twerrors.InvalidArgumentError("excluded_resolutions", "")
		}

		if len(filter.RepoNumbers) > 0 {
			out.RepoNumbers = make([]ts.RepoNumber, len(filter.RepoNumbers))
			for i, rn := range filter.RepoNumbers {
				out.RepoNumbers[i] = ts.RepoNumber{
					RepositoryID: ts.RepositoryEID(rn.RepositoryId),
					Number:       rn.Number,
				}
			}
		}

		if len(filter.SecurityCampaignIds) > 0 {
			out.SecurityCampaignIDs = make([]ts.SecurityCampaignEID, len(filter.SecurityCampaignIds))
			for i, id := range filter.SecurityCampaignIds {
				if id == 0 {
					return nil, twerrors.InvalidArgumentError("security_campaign_id", "must be > 0")
				}
				out.SecurityCampaignIDs[i] = ts.SecurityCampaignEID(id)
			}
		}

		if len(filter.ExcludedSecurityCampaignIds) > 0 {
			out.ExcludedSecurityCampaignIDs = make([]ts.SecurityCampaignEID, len(filter.ExcludedSecurityCampaignIds))
			for i, id := range filter.ExcludedSecurityCampaignIds {
				if id == 0 {
					return nil, twerrors.InvalidArgumentError("excluded_security_campaign_id", "must be > 0")
				}
				out.ExcludedSecurityCampaignIDs[i] = ts.SecurityCampaignEID(id)
			}
		}

		out.State = filter.State
		out.SarifIdentifiers = filter.RuleSarifIdentifiers
		out.ExcludedSarifIdentifiers = filter.ExcludedRuleSarifIdentifiers
		out.Tags = filter.RuleTags
		out.ExcludedTags = filter.ExcludedRuleTags
		out.Tools = filter.Tools
		out.ToolGUIDs = filter.ToolGuids
		out.ExcludedTools = filter.ExcludedTools
		out.Severities = filter.Severities
		out.ExcludedSeverities = filter.ExcludedSeverities
		out.QueryString = filter.SearchQuery
		out.Resolutions = resolutions
		out.ExcludedResolutions = excludedResolutions
		out.Classification = filter.Classification
		out.AlertLinks = filter.AlertLinks
		out.Autofixes = filter.Autofixes
		out.ExcludedAutofixes = filter.ExcludedAutofixes
		// Backwards compatibility with the old proto
		if filter.Autofix != proto.AutofixFilter_AUTOFIX_FILTER_NO_FILTER {
			out.Autofixes = append(out.Autofixes, filter.Autofix)
		}
		out.CampaignPresence = filter.CampaignPresence
	}

	return out, nil
}

func ResolutionsFilterFromProto(resolutions []proto.ResultResolutionFilter) ([]*ts.AlertResolution, error) {
	var result []*ts.AlertResolution
	for _, protoResolution := range resolutions {
		resolution, err := ResolutionFilterFromProto(protoResolution)
		if err != nil {
			return nil, err
		}
		result = append(result, resolution)
	}
	return result, nil
}

func ResolutionFilterFromProto(r proto.ResultResolutionFilter) (*ts.AlertResolution, error) {
	var resolution ts.AlertResolution
	switch r {
	case proto.ResultResolutionFilter_FILTER_NONE:
		return nil, nil
	case proto.ResultResolutionFilter_FILTER_FALSE_POSITIVE:
		resolution = ts.AlertResolutionFalsePositive
	case proto.ResultResolutionFilter_FILTER_NO_RESOLUTION:
		resolution = ts.AlertResolutionNone
	case proto.ResultResolutionFilter_FILTER_USED_IN_TESTS:
		resolution = ts.AlertResolutionUsedInTests
	case proto.ResultResolutionFilter_FILTER_WONT_FIX:
		resolution = ts.AlertResolutionWontFix
	default:
		return nil, errors.New("invalid resolution")
	}
	return &resolution, nil
}

func RepositoryVisibilityFilterFromProto(r proto.RepositoryVisibility) (string, error) {
	switch r {
	case proto.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC:
		return "public", nil
	case proto.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE:
		return "private", nil
	case proto.RepositoryVisibility_REPOSITORY_VISIBILITY_INTERNAL:
		return "internal", nil
	case proto.RepositoryVisibility_REPOSITORY_VISIBILITY_UNKNOWN:
		fallthrough
	default:
		return "", errors.New("invalid repository visibility")
	}
}
