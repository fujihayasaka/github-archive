package workflowparser

import (
	"strings"

	"gopkg.in/yaml.v3"
)

// Get some of the constants like reserved secret name check and parsing encapsulated
// Reusing the ideas and concepts of launch/flow/flowevents/events.go

// aligned with strings in ActionsService
// - UnreferencedSecretsToIgnore in actions-dotnet/src/Actions/Runtime/Client/WebApi/Pipelines/PipelineConstants.cs
const (
	GitHubToken        = "github_token"
	SystemGitHubToken  = "system.github.token"
	ActionsStepDebug   = "actions_step_debug"
	ActionsRunnerDebug = "actions_runner_debug"
)

// IsAllowedSecretName returns true if the secret name is not reserved
func IsAllowedSecretName(secretName string) bool {
	n := strings.ToLower(secretName)
	_, ok := secretsReserved[n]
	return !ok
}

// reserved secret names
var secretsReserved = map[string]bool{
	GitHubToken:        true,
	SystemGitHubToken:  true,
	ActionsStepDebug:   true,
	ActionsRunnerDebug: true,
}

type secretsMap map[string]OnSecret

// secrets referenced together with a workflow events (e.g. 'workflow_call')
type OnSecret struct {
	Description string `yaml:"description"`
	Required    bool   `yaml:"required"`
	Default     string `yaml:"default"`
	Line        int
}

// custom yaml parser including line number information for secrets definitions belonging to trigger events (on:)
func (sm *secretsMap) UnmarshalYAML(n *yaml.Node) error {
	rawSecrets := make(map[string]OnSecret)

	for _, node := range n.Content {
		if node.Tag == "!!str" {
			var secret OnSecret
			if err := n.Decode(&secret); err != nil {
				return err
			}
			secret.Line = node.Line
			rawSecrets[node.Value] = secret
		}
	}

	*sm = rawSecrets
	return nil
}
