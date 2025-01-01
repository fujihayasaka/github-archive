package azp

import "context"

type RunnerScaleSetsClient interface {
	GetRunnerScaleSet(ctx context.Context, scaleSetID int64) (*RunnerScaleSet, error)
	ListRunnerScaleSets(ctx context.Context, excludeElasticRunners bool) ([]*RunnerScaleSet, error)
}

type RunnerScaleSet struct {
	ID              int64                    `json:"id"`
	Name            string                   `json:"name"`
	RunnerGroupID   int64                    `json:"runnerGroupId"`
	RunnerGroupName string                   `json:"runnerGroupName"`
	Status          string                   `json:"status"`
	Statistics      RunnerScaleSetStatistics `json:"statistics"`
	Labels          []*Label                 `json:"labels"`
}

type RunnerScaleSetStatistics struct {
	TotalAvailableJobs     int64 `json:"totalAvailableJobs"`
	TotalAcquiredJobs      int64 `json:"totalAcquiredJobs"`
	TotalAssignedJobs      int64 `json:"totalAssignedJobs"`
	TotalRunningJobs       int64 `json:"totalRunningJobs"`
	TotalRegisteredRunners int64 `json:"totalRegisteredRunners"`
	TotalBusyRunners       int64 `json:"totalBusyRunners"`
	TotalIdleRunners       int64 `json:"totalIdleRunners"`
}
