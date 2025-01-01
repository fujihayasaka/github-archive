package workflowbuild

import (
	"context"
	"fmt"

	diet_earthsmoke "github.com/github/diet_earthsmoke/go"
	"github.com/github/go-kvp"

	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/types"
)

// SecretSource represents how a secret was created and the product it belongs to
// Each source maps to the key used to encrypt and decrypt the secret
type SecretSource string

const (
	NoSecretSource         SecretSource = "None"
	ActionsSecretSource    SecretSource = "Actions"
	DependabotSecretSource SecretSource = "Dependabot"
	CodespacesSecretSource SecretSource = "Codespaces"
)

// KeyName represents an Earthsmoke client key name
func (s SecretSource) KeyName() string {
	switch s {
	case ActionsSecretSource:
		return "custom-tasks-key"
	case DependabotSecretSource:
		return "dependabot-secrets-key"
	case CodespacesSecretSource:
		return "codespaces-secrets-key"
	}

	return ""
}

// String returns the string form of the secretSource
func (s SecretSource) String() string {
	return string(s)
}

func (s SecretSource) GetSourceHighLevelKey(secretKeysMap map[SecretSource]*diet_earthsmoke.HighLevelKey) (*diet_earthsmoke.HighLevelKey, error) {
	hlk, exists := secretKeysMap[s]
	if !exists {
		return nil, fmt.Errorf("No available crypto keys for the given source %s", s.String())
	}
	return hlk, nil
}

func DetermineSecretSource(ctx context.Context, obs *observability.Observability, eventType string, event flowevents.GitHubEvent, forkPolicy types.ForkPRWorkflowsPolicy, actor *metadata.WorkflowMetadataActor) SecretSource {
	// First, check for the conditions where no secrets should be used
	if flowevents.IsRestrictedForkPREvent(eventType, event) && !forkPolicy.ShouldSendSecrets() {
		return NoSecretSource
	}

	if !flowevents.AreSecretsEnabled(eventType) {
		return NoSecretSource
	}

	// Second, check for the conditions where Dependabot secrets should be used
	if flowevents.IsDependabotActor(actor) {
		return getDependabotSecretStore(ctx, obs, eventType)
	}

	// Default to using Actions secrets in all other cases
	return ActionsSecretSource
}

func CanGenerateIDToken(eventType string, event flowevents.GitHubEvent, forkPolicy types.ForkPRWorkflowsPolicy) bool {
	return !flowevents.IsRestrictedForkPREvent(eventType, event) || forkPolicy.ShouldSendSecrets()
}

func getDependabotSecretStore(ctx context.Context, obs *observability.Observability, eventType string) SecretSource {
	restrictionLevel := flowevents.GetDependabotRestrictionLevel(ctx, obs, eventType)

	switch restrictionLevel {
	case flowevents.DependabotActorNotExpected:
		obs.Logger.Error(ctx, "Unexpected event type triggered by Dependabot. Using full dependabot restrictions")
		return NoSecretSource

	case flowevents.DependabotFullyRestricted:
		return NoSecretSource

	case flowevents.DependabotPartiallyRestricted:
		return DependabotSecretSource

	case flowevents.DependabotUnrestricted:
		return ActionsSecretSource

	default:
		obs.Logger.Error(ctx, "Restriction level not supported. Using full dependabot restrictions",
			kvp.String("gh.launch.dependabot_restrictions", string(restrictionLevel)))
		return NoSecretSource
	}
}
