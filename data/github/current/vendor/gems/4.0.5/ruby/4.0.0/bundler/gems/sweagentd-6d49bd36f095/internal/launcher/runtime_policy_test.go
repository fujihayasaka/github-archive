package launcher

import (
	"context"
	"fmt"
	"slices"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
)

func TestEvaluateAsFlags_EmptyOutcomes(t *testing.T) {
	mock := newTestFFClient()
	pe := &RuntimePolicyEvaluator{ffClient: mock}

	// Enable the CCA tools enabled flag so the rule evaluates to false,
	// and don't enable the disallow flag.
	const repoID int64 = 101
	mock.enableRepoFlag(repoID, featureflags.CopilotSWEAgentCCATriggeringMCPToolsEnabled)

	ctx := context.Background()
	opts := &LaunchAgentOpts{
		GitHubRepoID:      repoID,
		GitHubRepoOwnerID: 11,
		ActorID:           33,
		GitHubRepoOwner:   "github",
		GitHubRepoName:    "example",
	}

	flags, err := pe.EvaluateAsFlags(ctx, opts)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// When the rule evaluates to false, no flags should be returned for it.
	for _, f := range flags {
		if f == fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "disable_cca_invoking_tools") {
			t.Fatalf("did not expect policy flag for disabled rule; got %v", flags)
		}
	}
}

func TestEvaluateAsFlags_OnlyTrueOutcomesIncluded(t *testing.T) {
	mock := newTestFFClient()
	pe := &RuntimePolicyEvaluator{ffClient: mock}

	const repoID int64 = 101
	// Enable the disallow flag so the rule evaluates to true
	mock.enableRepoFlag(repoID, featureflags.CopilotSWEAgentCCATriggeringMCPToolsDisallow)

	ctx := context.Background()
	opts := &LaunchAgentOpts{
		GitHubRepoID:      repoID,
		GitHubRepoOwnerID: 11,
		ActorID:           33,
		GitHubRepoOwner:   "github",
		GitHubRepoName:    "example",
	}

	flags, err := pe.EvaluateAsFlags(ctx, opts)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "disable_cca_triggering_mcp_tools")
	if !slices.Contains(flags, want) {
		t.Fatalf("expected policy flag %q; got %v", want, flags)
	}
}

func TestGetFeatureFlags_IncludesPolicyOutcomes(t *testing.T) {
	ctx := context.Background()
	const (
		repoID  int64 = 101
		ownerID int64 = 11
		actorID int64 = 33
	)

	mock := newTestFFClient()
	// Enable the CCA invoking tools disallow flag so the policy rule evaluates to true
	mock.enableRepoFlag(repoID, featureflags.CopilotSWEAgentCCATriggeringMCPToolsDisallow)

	opts := LaunchAgentOpts{
		GitHubRepoID:      repoID,
		GitHubRepoOwnerID: ownerID,
		ActorID:           actorID,
		GitHubRepoOwner:   "github",
		GitHubRepoName:    "example",
	}

	flags, err := getFeatureFlags(ctx, mock, &opts, true)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "disable_cca_triggering_mcp_tools")
	if !slices.Contains(flags, want) {
		t.Fatalf("expected policy flag %q in feature flags; got %v", want, flags)
	}
}

func TestGetFeatureFlags_ExcludesFalsePolicyOutcomes(t *testing.T) {
	ctx := context.Background()
	const (
		repoID  int64 = 101
		ownerID int64 = 11
		actorID int64 = 33
	)

	// Enable the CCA tools enabled flag so the rule evaluates to false
	mock := newTestFFClient()
	mock.enableRepoFlag(repoID, featureflags.CopilotSWEAgentCCATriggeringMCPToolsEnabled)

	opts := LaunchAgentOpts{
		GitHubRepoID:      repoID,
		GitHubRepoOwnerID: ownerID,
		ActorID:           actorID,
		GitHubRepoOwner:   "github",
		GitHubRepoName:    "example",
	}

	flags, err := getFeatureFlags(ctx, mock, &opts, true)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	notWant := fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "disable_cca_invoking_tools")
	if slices.Contains(flags, notWant) {
		t.Fatalf("did not expect policy flag %q in feature flags; got %v", notWant, flags)
	}
}

func TestRuleDisableTriggeredCCACodeChangeTools(t *testing.T) {
	const (
		repoID  int64 = 301
		ownerID int64 = 31
		actorID int64 = 41
	)

	baseOpts := func(triggered bool) *LaunchAgentOpts {
		return &LaunchAgentOpts{
			GitHubRepoID:      repoID,
			GitHubRepoOwnerID: ownerID,
			ActorID:           actorID,
			GitHubRepoOwner:   "github",
			GitHubRepoName:    "example",
			IsTriggered:       triggered,
		}
	}

	wantFlag := fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "disable_triggered_cca_code_change_tools")

	t.Run("enabled when flag is on and job is triggered", func(t *testing.T) {
		mock := newTestFFClient()
		mock.enableRepoFlag(repoID, featureflags.CopilotSWEAgentTriggersDisallowCodeChangeTools)
		pe := &RuntimePolicyEvaluator{ffClient: mock}

		flags, err := pe.EvaluateAsFlags(context.Background(), baseOpts(true))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !slices.Contains(flags, wantFlag) {
			t.Fatalf("expected policy flag %q; got %v", wantFlag, flags)
		}
	})

	t.Run("disabled when flag is off", func(t *testing.T) {
		mock := newTestFFClient()
		pe := &RuntimePolicyEvaluator{ffClient: mock}

		flags, err := pe.EvaluateAsFlags(context.Background(), baseOpts(true))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if slices.Contains(flags, wantFlag) {
			t.Fatalf("did not expect policy flag %q; got %v", wantFlag, flags)
		}
	})

	t.Run("disabled when flag is on but job is not triggered", func(t *testing.T) {
		mock := newTestFFClient()
		mock.enableRepoFlag(repoID, featureflags.CopilotSWEAgentTriggersDisallowCodeChangeTools)
		pe := &RuntimePolicyEvaluator{ffClient: mock}

		flags, err := pe.EvaluateAsFlags(context.Background(), baseOpts(false))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if slices.Contains(flags, wantFlag) {
			t.Fatalf("did not expect policy flag %q; got %v", wantFlag, flags)
		}
	})
}

func TestGetFeatureFlags_IncludesTriggeredCodeChangePolicyOutcome(t *testing.T) {
	ctx := context.Background()
	const (
		repoID  int64 = 302
		ownerID int64 = 32
		actorID int64 = 42
	)

	mock := newTestFFClient()
	mock.enableRepoFlag(repoID, featureflags.CopilotSWEAgentTriggersDisallowCodeChangeTools)

	opts := LaunchAgentOpts{
		GitHubRepoID:      repoID,
		GitHubRepoOwnerID: ownerID,
		ActorID:           actorID,
		GitHubRepoOwner:   "github",
		GitHubRepoName:    "example",
		IsTriggered:       true,
	}

	flags, err := getFeatureFlags(ctx, mock, &opts, true)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "disable_triggered_cca_code_change_tools")
	if !slices.Contains(flags, want) {
		t.Fatalf("expected policy flag %q in feature flags; got %v", want, flags)
	}
}

func TestRuleDisableTriggeredCCARuntimePublishTools(t *testing.T) {
	const (
		repoID  int64 = 303
		ownerID int64 = 33
		actorID int64 = 43
	)

	baseOpts := func(triggered bool) *LaunchAgentOpts {
		return &LaunchAgentOpts{
			GitHubRepoID:      repoID,
			GitHubRepoOwnerID: ownerID,
			ActorID:           actorID,
			GitHubRepoOwner:   "github",
			GitHubRepoName:    "example",
			IsTriggered:       triggered,
		}
	}

	wantFlag := fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "disable_triggered_cca_runtime_publish_tools")

	t.Run("enabled when flag is on and job is triggered", func(t *testing.T) {
		mock := newTestFFClient()
		mock.enableRepoFlag(repoID, featureflags.CopilotSWEAgentTriggersDisallowRuntimePublishTools)
		pe := &RuntimePolicyEvaluator{ffClient: mock}

		flags, err := pe.EvaluateAsFlags(context.Background(), baseOpts(true))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !slices.Contains(flags, wantFlag) {
			t.Fatalf("expected policy flag %q; got %v", wantFlag, flags)
		}
	})

	t.Run("disabled when flag is off", func(t *testing.T) {
		mock := newTestFFClient()
		pe := &RuntimePolicyEvaluator{ffClient: mock}

		flags, err := pe.EvaluateAsFlags(context.Background(), baseOpts(true))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if slices.Contains(flags, wantFlag) {
			t.Fatalf("did not expect policy flag %q; got %v", wantFlag, flags)
		}
	})

	t.Run("disabled when flag is on but job is not triggered", func(t *testing.T) {
		mock := newTestFFClient()
		mock.enableRepoFlag(repoID, featureflags.CopilotSWEAgentTriggersDisallowRuntimePublishTools)
		pe := &RuntimePolicyEvaluator{ffClient: mock}

		flags, err := pe.EvaluateAsFlags(context.Background(), baseOpts(false))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if slices.Contains(flags, wantFlag) {
			t.Fatalf("did not expect policy flag %q; got %v", wantFlag, flags)
		}
	})
}

func TestGetFeatureFlags_IncludesTriggeredRuntimePublishPolicyOutcome(t *testing.T) {
	ctx := context.Background()
	const (
		repoID  int64 = 304
		ownerID int64 = 34
		actorID int64 = 44
	)

	mock := newTestFFClient()
	mock.enableRepoFlag(repoID, featureflags.CopilotSWEAgentTriggersDisallowRuntimePublishTools)

	opts := LaunchAgentOpts{
		GitHubRepoID:      repoID,
		GitHubRepoOwnerID: ownerID,
		ActorID:           actorID,
		GitHubRepoOwner:   "github",
		GitHubRepoName:    "example",
		IsTriggered:       true,
	}

	flags, err := getFeatureFlags(ctx, mock, &opts, true)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "disable_triggered_cca_runtime_publish_tools")
	if !slices.Contains(flags, want) {
		t.Fatalf("expected policy flag %q in feature flags; got %v", want, flags)
	}
}

func TestGetFeatureFlags_SeparatesTriggeredPolicyFlags(t *testing.T) {
	ctx := context.Background()
	const (
		repoID  int64 = 305
		ownerID int64 = 35
		actorID int64 = 45
	)

	baseOpts := LaunchAgentOpts{
		GitHubRepoID:      repoID,
		GitHubRepoOwnerID: ownerID,
		ActorID:           actorID,
		GitHubRepoOwner:   "github",
		GitHubRepoName:    "example",
		IsTriggered:       true,
	}

	t.Run("code change flag does not imply runtime publish policy", func(t *testing.T) {
		mock := newTestFFClient()
		mock.enableRepoFlag(repoID, featureflags.CopilotSWEAgentTriggersDisallowCodeChangeTools)

		flags, err := getFeatureFlags(ctx, mock, &baseOpts, true)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

		codeChangePolicy := fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "disable_triggered_cca_code_change_tools")
		if !slices.Contains(flags, codeChangePolicy) {
			t.Fatalf("expected policy flag %q; got %v", codeChangePolicy, flags)
		}

		runtimePublishPolicy := fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "disable_triggered_cca_runtime_publish_tools")
		if slices.Contains(flags, runtimePublishPolicy) {
			t.Fatalf("did not expect policy flag %q; got %v", runtimePublishPolicy, flags)
		}
	})

	t.Run("runtime publish flag does not imply code change policy", func(t *testing.T) {
		mock := newTestFFClient()
		mock.enableRepoFlag(repoID, featureflags.CopilotSWEAgentTriggersDisallowRuntimePublishTools)

		flags, err := getFeatureFlags(ctx, mock, &baseOpts, true)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

		runtimePublishPolicy := fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "disable_triggered_cca_runtime_publish_tools")
		if !slices.Contains(flags, runtimePublishPolicy) {
			t.Fatalf("expected policy flag %q; got %v", runtimePublishPolicy, flags)
		}

		codeChangePolicy := fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "disable_triggered_cca_code_change_tools")
		if slices.Contains(flags, codeChangePolicy) {
			t.Fatalf("did not expect policy flag %q; got %v", codeChangePolicy, flags)
		}
	})
}

func TestRuleGranularMCPToolsets(t *testing.T) {
	const (
		repoID  int64 = 401
		ownerID int64 = 61
		actorID int64 = 71
	)

	baseOpts := func(triggered bool) *LaunchAgentOpts {
		return &LaunchAgentOpts{
			GitHubRepoID:      repoID,
			GitHubRepoOwnerID: ownerID,
			ActorID:           actorID,
			GitHubRepoOwner:   "some-org",
			GitHubRepoName:    "some-repo",
			IsTriggered:       triggered,
		}
	}

	wantFlag := fmt.Sprintf("%s:%s", runtimePolicyFlagPrefix, "granular_mcp_toolsets")

	t.Run("enabled when flag is on and job is triggered", func(t *testing.T) {
		mock := newTestFFClient()
		mock.enableAnyFlag(featureflags.CopilotSWEAgentGranularMCPToolsets)
		pe := &RuntimePolicyEvaluator{ffClient: mock}

		flags, err := pe.EvaluateAsFlags(context.Background(), baseOpts(true))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !slices.Contains(flags, wantFlag) {
			t.Fatalf("expected policy flag %q; got %v", wantFlag, flags)
		}
	})

	t.Run("disabled when flag is on but job is not triggered", func(t *testing.T) {
		mock := newTestFFClient()
		mock.enableAnyFlag(featureflags.CopilotSWEAgentGranularMCPToolsets)
		pe := &RuntimePolicyEvaluator{ffClient: mock}

		flags, err := pe.EvaluateAsFlags(context.Background(), baseOpts(false))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if slices.Contains(flags, wantFlag) {
			t.Fatalf("did not expect policy flag %q; got %v", wantFlag, flags)
		}
	})

	t.Run("disabled when flag is off and job is triggered", func(t *testing.T) {
		mock := newTestFFClient()
		pe := &RuntimePolicyEvaluator{ffClient: mock}

		flags, err := pe.EvaluateAsFlags(context.Background(), baseOpts(true))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if slices.Contains(flags, wantFlag) {
			t.Fatalf("did not expect policy flag %q; got %v", wantFlag, flags)
		}
	})
}
