package workflowinvoker

import (
	"context"
)

const (
	stepDebugSecretName   = "ACTIONS_STEP_DEBUG"
	runnerDebugSecretName = "ACTIONS_RUNNER_DEBUG"
)

// Add secrets to enable debug logging, regardless of previous secret values.
func addDebugSecrets(ctx context.Context, obs *Observability, secretsMap map[string]string) {
	secrets := []string{stepDebugSecretName, runnerDebugSecretName}

	for _, secret := range secrets {
		secretsMap[secret] = "true"
	}

	obs.Debug(ctx, "added secrets to enable debug logging")
}
