package runnergroups

import (
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/types"

	"github.com/github/launch/services/deploy/runnerscalesets"
	"github.com/github/launch/services/deploy/selfhostedrunners"
)

func (s *service) mapRunnerGroup(runnerGroup *azp.RunnerGroup) *RunnerGroup {
	ars := []*azp.RunnerGroup{runnerGroup}
	mapped := s.mapRunnerGroups(ars)

	return mapped[0]
}

func (s *service) mapRunnerGroups(ars []*azp.RunnerGroup) []*RunnerGroup {
	rgs := make([]*RunnerGroup, 0, len(ars))
	for _, ar := range ars {
		rg := &RunnerGroup{
			Id:                           ar.ID,
			Name:                         ar.Name,
			Size:                         ar.Size,
			OwnerId:                      types.IdentityFromGlobalID(ar.OwningTenant),
			SelectedTargets:              types.IdentitiesFromGlobalIDs(ar.Visibility.SelectedTargets),
			IsDefault:                    ar.IsDefault,
			IsHosted:                     ar.IsHosted,
			OwnerGroupId:                 ar.OwnerGroupID,
			SelectedWorkflowRefs:         ar.Visibility.SelectedWorkflowRefs,
			RestrictedToWorkflows:        ar.Visibility.RestrictedToWorkflows,
			WorkflowRestrictionsReadOnly: ar.Visibility.WorkflowRestrictionsReadOnly,
		}

		rg.Runners = selfhostedrunners.MapDetailedAzpRunners(ar.Runners)
		rg.RunnerScaleSets = runnerscalesets.MapAzpRunnerScaleSets(ar.RunnerScaleSets)
		rg.Visibility = stringToVisibilityMap[ar.Visibility.VisibilityType]
		rg.AllowPublic = ar.Visibility.AllowPublic
		rg.InheritedAllowPublic = ar.InheritedAllowPublic
		rgs = append(rgs, rg)
	}

	return rgs
}

var stringToVisibilityMap = map[string]Visibility{
	"all":      Visibility_ALL,
	"private":  Visibility_PRIVATE,
	"selected": Visibility_SELECTED,
}
