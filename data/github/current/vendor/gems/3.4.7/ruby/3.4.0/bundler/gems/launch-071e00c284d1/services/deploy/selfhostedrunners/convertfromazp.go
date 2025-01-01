package selfhostedrunners

import (
	"github.com/github/launch/pkg/azp"
)

func ConvertDetailedRunnerFromAzp(azpRunner *azp.RunnerV2) *Runner {
	runner := &Runner{
		Id:                 azpRunner.ID,
		Name:               azpRunner.Name,
		Os:                 azpRunner.GetOS(),
		Arch:               azpRunner.GetArch(),
		Status:             azpRunner.Status,
		CurrentParallelism: azpRunner.CurrentParallelism,
		RunnerGroupId:      azpRunner.RunnerGroupID,
		Ephemeral:          azpRunner.Ephemeral,
	}

	runner.Labels = convertLabelsFromAzp(azpRunner.Labels)

	if azpRunner.AssignedRequest != nil {
		runner.AssignedRequest = &Runner_AssignedRequest{
			JobName:         azpRunner.AssignedRequest.JobName,
			ExternalBuildId: externalBuildID(azpRunner),
			CheckRunId:      azpRunner.AssignedRequest.CheckRunGlobalID,
		}
	}
	return runner
}

func MapDetailedAzpRunners(ars []*azp.RunnerV2) []*Runner {
	runners := make([]*Runner, 0, len(ars))
	for _, ar := range ars {
		runner := ConvertDetailedRunnerFromAzp(ar)
		runners = append(runners, runner)
	}
	return runners
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

func externalBuildID(azpRunner *azp.RunnerV2) string {
	return azpRunner.AssignedRequest.PlanID + "," + azpRunner.AssignedRequest.JobID
}
