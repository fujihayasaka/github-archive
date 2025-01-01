package flowevents

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestIsAllowedEvent(t *testing.T) {
	// This is not exhaustive. Rather, it's a demonstration of some of the interesting bits of the func.
	allowed := []string{
		"push",
		"PUSH",
		"pull_request",
		"registry_package",
		"schedule",
		// TODO support filters:
		// "pull_request.open",
	}

	for _, s := range allowed {
		assert.True(t, IsAllowedEvent(s), "should allow %q", s)
	}

	// This is also not exhaustive. We want to have this done by universe, after all.
	notAllowed := []string{
		"installation",
		"randommashingofkeyboard",
	}

	for _, s := range notAllowed {
		assert.False(t, IsAllowedEvent(s), "should not allow %q", s)
	}
}

func TestIsAllowedWebhookEvent(t *testing.T) {
	assert.True(t, IsAllowedWebhookEvent("push"))
	assert.False(t, IsAllowedWebhookEvent("shush"))
	assert.False(t, IsAllowedWebhookEvent("schedule"))
	assert.False(t, IsAllowedWebhookEvent("dynamic"))
	assert.False(t, IsAllowedWebhookEvent("workflow_call"))
}

func TestGetEventTypeGlobs(t *testing.T) {
	assert.ElementsMatch(t, []string{"opened", "reopened", "synchronize"}, GetEventTypeGlobs("pull_request"))
	assert.ElementsMatch(t, []string{}, GetEventTypeGlobs("push"))
	assert.ElementsMatch(t, []string{}, GetEventTypeGlobs("schedule"))
}

func TestDependabotRestrictions(t *testing.T) {
	for eventType, info := range eventsAllowed {
		t.Run(eventType, func(t *testing.T) {
			if !info.secretsEnabled {
				if info.dependabotRestrictions != DependabotFullyRestricted &&
					info.dependabotRestrictions != DependabotActorNotExpected {
					assert.Fail(t, "expected event type '%v' to be fully restricted if secrets aren't enabled", eventType)
				}
			}

			if info.dependabotRestrictions == DependabotUnrestricted &&
				!info.nonWebhookEvent &&
				eventType != PullRequestTarget {
				_, isDefaultBranchWebhookEvent := eventTypesForDefaultBranch[eventType]

				assert.True(t, isDefaultBranchWebhookEvent, "Expected event type '%v' to be partially or fully restricted. Event could be triggered with a Dependabot PR ref and build untrusted code, which could be leveraged in a supply chain attack", eventType)
			}
		})
	}
}
