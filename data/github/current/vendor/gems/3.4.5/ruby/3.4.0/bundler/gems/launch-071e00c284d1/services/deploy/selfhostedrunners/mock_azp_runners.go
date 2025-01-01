package selfhostedrunners

import (
	"github.com/github/launch/pkg/azp"
)

func mockRunners() []*azp.RunnerV2 {
	return []*azp.RunnerV2{
		{
			ID:   1,
			Name: "runner 1",
			Labels: []*azp.Label{
				{
					ID:   1,
					Name: "windows",
					Type: "system",
				},
				{
					ID:   2,
					Name: "x86",
					Type: "system",
				},
			},
			Status: "online",
			AssignedRequest: &azp.AssignedRequest{
				JobName:          "job 1",
				PlanID:           "PlanID1",
				JobID:            "JobID1",
				CheckRunGlobalID: "CR_1",
			},
			CurrentParallelism: 1,
		},
		{
			ID:   2,
			Name: "runner 2",
			Labels: []*azp.Label{
				{
					ID:   1,
					Name: "macOS",
					Type: "system",
				},
				{
					ID:   2,
					Name: "x64",
					Type: "system",
				},
			},
			Status:             "online",
			CurrentParallelism: 0,
		},
		{
			ID:   3,
			Name: "runner 3",
			Labels: []*azp.Label{
				{
					ID:   1,
					Name: "macOS",
					Type: "system",
				},
				{
					ID:   2,
					Name: "x64",
					Type: "system",
				},
			},
			Status:             "offline",
			CurrentParallelism: 0,
		},
	}
}

func mapToAzpRunners(rc []*Runner) []*azp.RunnerV2 {
	var azprc []*azp.RunnerV2
	for _, r := range rc {
		azpr := &azp.RunnerV2{
			ID:                 r.Id,
			Name:               r.Name,
			Status:             r.Status,
			CurrentParallelism: r.CurrentParallelism,
		}
		for _, l := range r.Labels {
			label := &azp.Label{
				ID:   l.Id,
				Name: l.Name,
				Type: l.Type,
			}
			azpr.Labels = append(azpr.Labels, label)
		}
		if r.AssignedRequest != nil {
			azpr.AssignedRequest = &azp.AssignedRequest{
				JobName:          r.AssignedRequest.JobName,
				PlanID:           "PlanID1",
				JobID:            "JobID1",
				CheckRunGlobalID: "CR_1",
			}
		}
		azprc = append(azprc, azpr)
	}
	return azprc
}
