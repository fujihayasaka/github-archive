package runnerscalesets

import (
	"github.com/github/launch/pkg/azp"
)

func MapAzpRunnerScaleSets(azpRunnerScaleSets []*azp.RunnerScaleSet) []*RunnerScaleSet {
	var rss []*RunnerScaleSet
	for _, azpRunnerScaleSet := range azpRunnerScaleSets {
		rs := ConvertDetailedRunnerScaleSetFromAzp(azpRunnerScaleSet)
		rss = append(rss, rs)
	}
	return rss
}

func ConvertDetailedRunnerScaleSetFromAzp(azpRunnerScaleSet *azp.RunnerScaleSet) *RunnerScaleSet {
	rs := &RunnerScaleSet{
		Id:              azpRunnerScaleSet.ID,
		Name:            azpRunnerScaleSet.Name,
		RunnerGroupId:   azpRunnerScaleSet.RunnerGroupID,
		RunnerGroupName: azpRunnerScaleSet.RunnerGroupName,
		Status:          azpRunnerScaleSet.Status,
		Statistics:      convertScaleSetStatisticsFromAzp(&azpRunnerScaleSet.Statistics),
		Labels:          convertLabelsFromAzp(azpRunnerScaleSet.Labels),
	}
	return rs
}

func convertScaleSetStatisticsFromAzp(azpScaleSetStatistics *azp.RunnerScaleSetStatistics) *RunnerScaleSetStatistics {
	rs := &RunnerScaleSetStatistics{
		TotalAvailableJobs:     azpScaleSetStatistics.TotalAvailableJobs,
		TotalAcquiredJobs:      azpScaleSetStatistics.TotalAcquiredJobs,
		TotalAssignedJobs:      azpScaleSetStatistics.TotalAssignedJobs,
		TotalRunningJobs:       azpScaleSetStatistics.TotalRunningJobs,
		TotalRegisteredRunners: azpScaleSetStatistics.TotalRegisteredRunners,
		TotalBusyRunners:       azpScaleSetStatistics.TotalBusyRunners,
		TotalIdleRunners:       azpScaleSetStatistics.TotalIdleRunners,
	}
	return rs
}

func convertLabelsFromAzp(azpLabels []*azp.Label) []*Label {
	var ls []*Label
	for _, al := range azpLabels {
		l := &Label{
			Id:   al.ID,
			Name: al.Name,
			Type: al.Type,
		}
		ls = append(ls, l)
	}

	return ls
}
