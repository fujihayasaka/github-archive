package refactortests

import (
	"testing"

	"github.com/github/launch/pkg/azp"
)

func TestClientCompat(t *testing.T) {
	suites := map[string]func(*testing.T, func(string) azp.RepositoryClient){
		"checks":        ChecksCompatTest,
		"runnerGroups":  RunnerGroupCompatTest,
		"artifacts":     ArtifactsCompatTest,
		"builds":        BuildsCompatTest,
		"labels":        LabelsCompatTest,
		"largerrunners": LargerRunnersCompatTest,
		"urlexchange":   URLExchangeCompatTest,
		"runners":       RunnersCompatTest,
	}
	for suiteName, suite := range suites {
		t.Run(suiteName, func(t *testing.T) {
			suite(t, newClient)
		})
	}
}

func TestClientCompatWithFlags(t *testing.T) {
	suites := map[string]func(*testing.T, func(string, map[string]bool) azp.RepositoryClient){
		"gates": GatesCompatTest,
	}

	for suiteName, suite := range suites {
		t.Run(suiteName, func(t *testing.T) {
			suite(t, newClientWithFlags)
		})
	}
}

func TestExisting_QueueSuite(t *testing.T) {
	azp.TestBuildsQueue(t, newClient)
}

func TestExisting_RunnerGroup(t *testing.T) {
	azp.TestRunnerGroups(t, newClient)
}
