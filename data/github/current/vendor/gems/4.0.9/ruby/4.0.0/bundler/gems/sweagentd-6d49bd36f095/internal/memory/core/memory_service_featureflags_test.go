package core_test

import (
	"context"
	"maps"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/feature-management-client-go/vexi/v2"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFeatureFlagDisabledWhenCreatingMemory(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		SaveForRepositoryFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(nil)) // nil flags = feature disabled

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error when feature flag is disabled")
}

func TestFeatureFlagDisabledWhenGettingMemory(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return nil, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(nil)) // nil flags = feature disabled

	_, err := svc.GetMemories(t.Context(), user, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error when feature flag is disabled")
}

// Flag Matrix Tests

func newMemoryServiceForFlagMatrix(t *testing.T, flags map[string]bool) (core.MemoryService, core.User, *core.Repository, *core.Memory) {
	t.Helper()

	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		SaveForRepositoryFunc: func(repoID core.RepositoryID, m *core.Memory) error {
			return nil
		},
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return []*core.Memory{memory}, nil
		},
		FindRecentByRepositoryFunc: func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
			return []*core.Memory{memory}, nil
		},
		DeleteForRepositoryFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			return nil
		},
	}

	// Ensure secret scanning is off unless explicitly overridden.
	flagConfig := map[string]bool{}
	maps.Copy(flagConfig, flags)
	if _, ok := flagConfig["copilot_swe_agent_memory_secret_scanning"]; !ok {
		flagConfig["copilot_swe_agent_memory_secret_scanning"] = false
	}

	ffClient := featureflags.NewNoopClient(flagConfig)

	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
			return nil, nil
		},
	}

	service := core.NewMemoryService(memoryStore, ffClient, secretScanner, observability.NewNoopExporters(), &MockMemoryEnablementChecker{Enabled: true}, nil)

	return service, user, repository, memory
}

func TestMemoryService_NoFlagsSpecified_AllOperationsDisabled(t *testing.T) {
	service, user, repository, memory := newMemoryServiceForFlagMatrix(t, nil)
	ctx := t.Context()

	err := service.CreateMemory(ctx, memory, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)

	_, err = service.GetMemories(ctx, user, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)

	_, err = service.GetRecentMemories(ctx, user, repository, expectedLimit)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)

	err = service.DeleteMemory(ctx, user, repository, memory.ID)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)

	err = service.DeleteAllMemories(ctx, user, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestMemoryService_NewFlagOnly_AllOperationsSucceed(t *testing.T) {
	flags := map[string]bool{
		"copilot-feature-agentic-memory": true,
	}

	service, user, repository, memory := newMemoryServiceForFlagMatrix(t, flags)
	ctx := t.Context()

	require.NoError(t, service.CreateMemory(ctx, memory, repository))

	_, err := service.GetMemories(ctx, user, repository)
	require.NoError(t, err)

	_, err = service.GetRecentMemories(ctx, user, repository, expectedLimit)
	require.NoError(t, err)

	require.NoError(t, service.DeleteMemory(ctx, user, repository, memory.ID))
	require.NoError(t, service.DeleteAllMemories(ctx, user, repository))
}

func TestMemoryService_DisableFlagTakesPrecedence_AllOperationsDisabled(t *testing.T) {
	flags := map[string]bool{
		"copilot-feature-agentic-memory":          true,
		"copilot-feature-agentic-memory-disabled": true,
	}

	service, user, repository, memory := newMemoryServiceForFlagMatrix(t, flags)
	ctx := t.Context()

	err := service.CreateMemory(ctx, memory, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "disable flag should take precedence over enable flag")

	_, err = service.GetMemories(ctx, user, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "disable flag should take precedence over enable flag")

	_, err = service.GetRecentMemories(ctx, user, repository, expectedLimit)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "disable flag should take precedence over enable flag")

	err = service.DeleteMemory(ctx, user, repository, memory.ID)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "disable flag should take precedence over enable flag")

	err = service.DeleteAllMemories(ctx, user, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "disable flag should take precedence over enable flag")
}

func TestMemoryService_DisableFlagFalse_OperationsSucceed(t *testing.T) {
	flags := map[string]bool{
		"copilot-feature-agentic-memory":          true,
		"copilot-feature-agentic-memory-disabled": false,
	}

	service, user, repository, memory := newMemoryServiceForFlagMatrix(t, flags)
	ctx := t.Context()

	require.NoError(t, service.CreateMemory(ctx, memory, repository))

	_, err := service.GetMemories(ctx, user, repository)
	require.NoError(t, err)

	_, err = service.GetRecentMemories(ctx, user, repository, expectedLimit)
	require.NoError(t, err)

	require.NoError(t, service.DeleteMemory(ctx, user, repository, memory.ID))
	require.NoError(t, service.DeleteAllMemories(ctx, user, repository))
}

func TestMemoryService_CheckMemoryEnabled_WithDisableFlag(t *testing.T) {
	t.Run("enable flag only - returns true", func(t *testing.T) {
		flags := map[string]bool{
			"copilot-feature-agentic-memory": true,
		}
		service, _, repository, _ := newMemoryServiceForFlagMatrix(t, flags)

		enabled, err := service.CheckMemoryEnabled(t.Context(), 1, repository)
		require.NoError(t, err)
		require.True(t, enabled, "should be enabled when only enable flag is true")
	})

	t.Run("both enable and disable flags true - returns false", func(t *testing.T) {
		flags := map[string]bool{
			"copilot-feature-agentic-memory":          true,
			"copilot-feature-agentic-memory-disabled": true,
		}
		service, _, repository, _ := newMemoryServiceForFlagMatrix(t, flags)

		enabled, err := service.CheckMemoryEnabled(t.Context(), 1, repository)
		require.NoError(t, err)
		require.False(t, enabled, "disable flag should take precedence")
	})

	t.Run("enable true, disable false - returns true", func(t *testing.T) {
		flags := map[string]bool{
			"copilot-feature-agentic-memory":          true,
			"copilot-feature-agentic-memory-disabled": false,
		}
		service, _, repository, _ := newMemoryServiceForFlagMatrix(t, flags)

		enabled, err := service.CheckMemoryEnabled(t.Context(), 1, repository)
		require.NoError(t, err)
		require.True(t, enabled, "should be enabled when disable flag is false")
	})

	t.Run("enable false, disable true - returns false", func(t *testing.T) {
		flags := map[string]bool{
			"copilot-feature-agentic-memory":          false,
			"copilot-feature-agentic-memory-disabled": true,
		}
		service, _, repository, _ := newMemoryServiceForFlagMatrix(t, flags)

		enabled, err := service.CheckMemoryEnabled(t.Context(), 1, repository)
		require.NoError(t, err)
		require.False(t, enabled, "should be disabled when enable flag is false")
	})
}

func TestMemoryService_CheckMemoryEnabled_WithDisallowFlag(t *testing.T) {
	t.Run("disallow flag on - returns false even when enabled flag on", func(t *testing.T) {
		flags := map[string]bool{
			"copilot-feature-agentic-memory": true,
			"copilot_swe_agent_disallow":     true,
		}
		service, _, repository, _ := newMemoryServiceForFlagMatrix(t, flags)

		enabled, err := service.CheckMemoryEnabled(t.Context(), 1, repository)
		require.NoError(t, err)
		require.False(t, enabled, "disallow flag should make memory check return false")
	})

	t.Run("disallow flag off - returns true", func(t *testing.T) {
		flags := map[string]bool{
			"copilot-feature-agentic-memory": true,
			"copilot_swe_agent_disallow":     false,
		}
		service, _, repository, _ := newMemoryServiceForFlagMatrix(t, flags)

		enabled, err := service.CheckMemoryEnabled(t.Context(), 1, repository)
		require.NoError(t, err)
		require.True(t, enabled, "should be enabled when disallow flag is false")
	})

	t.Run("disallow flag dominates even when explicit disable flag is false", func(t *testing.T) {
		flags := map[string]bool{
			"copilot-feature-agentic-memory":          true,
			"copilot-feature-agentic-memory-disabled": false,
			"copilot_swe_agent_disallow":              true,
		}
		service, _, repository, _ := newMemoryServiceForFlagMatrix(t, flags)

		enabled, err := service.CheckMemoryEnabled(t.Context(), 1, repository)
		require.NoError(t, err)
		require.False(t, enabled, "disallow flag should disable memory regardless of explicit disable flag")
	})
}

func TestUserScopedMemory_CCR_IntegrationSpecificFlag(t *testing.T) {
	ccrCtx := func(t *testing.T) context.Context {
		t.Helper()
		return featureflags.ContextWithIntegrationID(t.Context(), "copilot-pr-reviews")
	}

	t.Run("CCR blocked when general flag on but CCR flag off", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{
			SaveForUserFunc: func(userID uint64, m *core.Memory) error {
				return nil
			},
			FindRecentByUserFunc: func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
				return []*core.Memory{memory}, nil
			},
			FindByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
				return []*core.Memory{memory}, nil
			},
			DeleteForUserFunc: func(userID uint64, id core.MemoryID) error {
				return nil
			},
			DeleteAllForUserFunc: func(userID uint64) error {
				return nil
			},
		}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":             true,
				"copilot_feature_agentic_memory_user_scoped": true,
				// CopilotSWEAgentMemoryUserScopedCCR NOT set
			}))

		ctx := ccrCtx(t)

		err := svc.CreateUserMemory(ctx, memory, user)
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "CreateUserMemory should fail for CCR without CCR-specific flag")

		_, err = svc.GetRecentUserMemories(ctx, user, 10, core.UserMemoryQuery{})
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "GetRecentUserMemories should fail for CCR without CCR-specific flag")

		_, err = svc.GetUserMemories(ctx, user, core.UserMemoryQuery{})
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "GetUserMemories should fail for CCR without CCR-specific flag")

		err = svc.DeleteUserMemory(ctx, user, memory.ID)
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "DeleteUserMemory should fail for CCR without CCR-specific flag")

		err = svc.DeleteAllUserMemories(ctx, user)
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "DeleteAllUserMemories should fail for CCR without CCR-specific flag")
	})

	t.Run("CCR succeeds when both general and CCR flags on", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{
			SaveForUserFunc: func(userID uint64, m *core.Memory) error {
				return nil
			},
			FindRecentByUserFunc: func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
				return []*core.Memory{memory}, nil
			},
			FindByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
				return []*core.Memory{memory}, nil
			},
			DeleteForUserFunc: func(userID uint64, id core.MemoryID) error {
				return nil
			},
			DeleteAllForUserFunc: func(userID uint64) error {
				return nil
			},
		}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":               true,
				"copilot_feature_agentic_memory_user_scoped":   true,
				core.FeatureUserScopedMemoryCCR:                true,
				"copilot_swe_agent_memory_voting_coding_agent": true,
				"copilot_swe_agent_memory_secret_scanning":     false,
			}))

		ctx := ccrCtx(t)

		require.NoError(t, svc.CreateUserMemory(ctx, memory, user), "CreateUserMemory should succeed for CCR with both flags")

		memories, err := svc.GetRecentUserMemories(ctx, user, 10, core.UserMemoryQuery{})
		require.NoError(t, err, "GetRecentUserMemories should succeed for CCR with both flags")
		require.Len(t, memories, 1)

		memories, err = svc.GetUserMemories(ctx, user, core.UserMemoryQuery{})
		require.NoError(t, err, "GetUserMemories should succeed for CCR with both flags")
		require.Len(t, memories, 1)

		require.NoError(t, svc.DeleteUserMemory(ctx, user, memory.ID), "DeleteUserMemory should succeed for CCR with both flags")
		require.NoError(t, svc.DeleteAllUserMemories(ctx, user), "DeleteAllUserMemories should succeed for CCR with both flags")
	})

	t.Run("non-CCR integration needs only general flag", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{
			SaveForUserFunc: func(userID uint64, m *core.Memory) error {
				return nil
			},
			FindRecentByUserFunc: func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
				return []*core.Memory{memory}, nil
			},
		}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":             true,
				"copilot_feature_agentic_memory_user_scoped": true,
				// No CCR-specific flag — not needed for non-CCR
			}))

		ctx := codingAgentCtx(t)

		require.NoError(t, svc.CreateUserMemory(ctx, memory, user), "CreateUserMemory should succeed for non-CCR without CCR flag")

		memories, err := svc.GetRecentUserMemories(ctx, user, 10, core.UserMemoryQuery{})
		require.NoError(t, err, "GetRecentUserMemories should succeed for non-CCR without CCR flag")
		require.Len(t, memories, 1)
	})
}
func TestUserScopedMemory_CFI_PlanBasedRouting(t *testing.T) {
	cfiProCtx := func(t *testing.T) context.Context {
		t.Helper()
		ctx := requestctx.NewContext(codingAgentCtx(t))
		err := requestctx.AddCopilotUserDetails(ctx, 1, &copilotUsersTwirp.CopilotUserDetails{
			Id:            1,
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			HasPaidAccess: true,
		})
		require.NoError(t, err)
		return ctx
	}

	cfiProPlusCtx := func(t *testing.T) context.Context {
		t.Helper()
		ctx := requestctx.NewContext(codingAgentCtx(t))
		err := requestctx.AddCopilotUserDetails(ctx, 1, &copilotUsersTwirp.CopilotUserDetails{
			Id:            1,
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
			HasPaidAccess: true,
		})
		require.NoError(t, err)
		return ctx
	}

	cfbCtx := func(t *testing.T) context.Context {
		t.Helper()
		ctx := requestctx.NewContext(codingAgentCtx(t))
		err := requestctx.AddCopilotUserDetails(ctx, 1, &copilotUsersTwirp.CopilotUserDetails{
			Id:            1,
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
			HasPaidAccess: true,
		})
		require.NoError(t, err)
		return ctx
	}

	cfeCtx := func(t *testing.T) context.Context {
		t.Helper()
		ctx := requestctx.NewContext(codingAgentCtx(t))
		err := requestctx.AddCopilotUserDetails(ctx, 1, &copilotUsersTwirp.CopilotUserDetails{
			Id:            1,
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
			HasPaidAccess: true,
		})
		require.NoError(t, err)
		return ctx
	}

	educationFreeCtx := func(t *testing.T) context.Context {
		t.Helper()
		ctx := requestctx.NewContext(codingAgentCtx(t))
		err := requestctx.AddCopilotUserDetails(ctx, 1, &copilotUsersTwirp.CopilotUserDetails{
			Id:            1,
			CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			HasFreeAccess: true,
			HasPaidAccess: false,
		})
		require.NoError(t, err)
		return ctx
	}

	t.Run("CfI Pro user with CFI flag enabled succeeds", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{
			SaveForUserFunc: func(userID uint64, m *core.Memory) error {
				return nil
			},
		}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory": true,
				core.FeatureUserScopedMemoryCFI:  true,
				core.FeatureUserScopedMemory:     false,
			}))

		ctx := cfiProCtx(t)
		require.NoError(t, svc.CreateUserMemory(ctx, memory, user))
	})

	t.Run("CfI Pro user with only standard flag enabled is blocked", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":             true,
				"copilot_feature_agentic_memory_user_scoped": true,
				core.FeatureUserScopedMemoryCFI:              false,
			}))

		ctx := cfiProCtx(t)
		err := svc.CreateUserMemory(ctx, memory, user)
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	})

	t.Run("CfB user with standard flag enabled succeeds", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{
			SaveForUserFunc: func(userID uint64, m *core.Memory) error {
				return nil
			},
		}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":             true,
				"copilot_feature_agentic_memory_user_scoped": true,
				core.FeatureUserScopedMemoryCFI:              false,
			}))

		ctx := cfbCtx(t)
		require.NoError(t, svc.CreateUserMemory(ctx, memory, user))
	})

	t.Run("CfB user with only CFI flag enabled is blocked", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":             true,
				"copilot_feature_agentic_memory_user_scoped": false,
				core.FeatureUserScopedMemoryCFI:              true,
			}))

		ctx := cfbCtx(t)
		err := svc.CreateUserMemory(ctx, memory, user)
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	})

	t.Run("CfI Pro+ user with CFI flag enabled succeeds", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{
			SaveForUserFunc: func(userID uint64, m *core.Memory) error {
				return nil
			},
		}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory": true,
				core.FeatureUserScopedMemoryCFI:  true,
				core.FeatureUserScopedMemory:     false,
			}))

		ctx := cfiProPlusCtx(t)
		require.NoError(t, svc.CreateUserMemory(ctx, memory, user))
	})

	t.Run("CfI Pro+ user with only standard flag enabled is blocked", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":             true,
				"copilot_feature_agentic_memory_user_scoped": true,
				core.FeatureUserScopedMemoryCFI:              false,
			}))

		ctx := cfiProPlusCtx(t)
		err := svc.CreateUserMemory(ctx, memory, user)
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	})

	t.Run("CfE user with standard flag enabled succeeds", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{
			SaveForUserFunc: func(userID uint64, m *core.Memory) error {
				return nil
			},
		}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":             true,
				"copilot_feature_agentic_memory_user_scoped": true,
				core.FeatureUserScopedMemoryCFI:              false,
			}))

		ctx := cfeCtx(t)
		require.NoError(t, svc.CreateUserMemory(ctx, memory, user))
	})

	t.Run("CfE user with only CFI flag enabled is blocked", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":             true,
				"copilot_feature_agentic_memory_user_scoped": false,
				core.FeatureUserScopedMemoryCFI:              true,
			}))

		ctx := cfeCtx(t)
		err := svc.CreateUserMemory(ctx, memory, user)
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	})

	t.Run("Education Free user routes to standard flag not CFI", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{
			SaveForUserFunc: func(userID uint64, m *core.Memory) error {
				return nil
			},
		}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":             true,
				"copilot_feature_agentic_memory_user_scoped": true,
				core.FeatureUserScopedMemoryCFI:              false,
			}))

		// Education Free has IsPaidIndividual plan but HasPaidAccess=false,
		// so should route to standard flag, not CFI
		ctx := educationFreeCtx(t)
		require.NoError(t, svc.CreateUserMemory(ctx, memory, user))
	})

	t.Run("Education Free user blocked when only CFI flag enabled", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":             true,
				"copilot_feature_agentic_memory_user_scoped": false,
				core.FeatureUserScopedMemoryCFI:              true,
			}))

		// Education Free should NOT route to CFI despite having Individual plan
		ctx := educationFreeCtx(t)
		err := svc.CreateUserMemory(ctx, memory, user)
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	})

	t.Run("invalid plan user routes to standard flag", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{
			SaveForUserFunc: func(userID uint64, m *core.Memory) error {
				return nil
			},
		}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":             true,
				"copilot_feature_agentic_memory_user_scoped": true,
				core.FeatureUserScopedMemoryCFI:              false,
			}))

		ctx := requestctx.NewContext(codingAgentCtx(t))
		err := requestctx.AddCopilotUserDetails(ctx, 1, &copilotUsersTwirp.CopilotUserDetails{
			Id:          1,
			CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INVALID,
		})
		require.NoError(t, err)

		require.NoError(t, svc.CreateUserMemory(ctx, memory, user))
	})

	t.Run("user with neither flag is blocked", func(t *testing.T) {
		user := testUser()
		repoNWO := testRepoNWO(t)
		memory := testMemory(repoNWO, user)

		memoryStore := &MockMemoryStore{}

		svc := newTestMemoryService(t, memoryStore,
			withFeatureFlags(map[string]bool{
				"copilot-feature-agentic-memory":             true,
				"copilot_feature_agentic_memory_user_scoped": false,
				core.FeatureUserScopedMemoryCFI:              false,
			}))

		ctx := cfiProCtx(t)
		err := svc.CreateUserMemory(ctx, memory, user)
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	})
}

// TestCheckMemoryEnabled_AgreesWithGate pins the invariant that the probe
// (CheckMemoryEnabled) and the per-operation gate (validateRepositoryAccess)
// evaluate the same memory feature-flag predicate. If they diverge, the
// UI/agent prompt that consults the probe to decide whether to surface
// memory features will disagree with the backend enforcement that runs on
// every read/write/vote.
func TestCheckMemoryEnabled_AgreesWithGate(t *testing.T) {
	cases := []struct {
		name  string
		flags map[string]bool
		want  bool
	}{
		{name: "enabled only", flags: map[string]bool{"copilot-feature-agentic-memory": true}, want: true},
		{name: "enabled and disabled", flags: map[string]bool{
			"copilot-feature-agentic-memory":          true,
			"copilot-feature-agentic-memory-disabled": true,
		}, want: false},
		{name: "neither", flags: map[string]bool{}, want: false},
		{name: "enabled false", flags: map[string]bool{"copilot-feature-agentic-memory": false}, want: false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			service, user, repository, memory := newMemoryServiceForFlagMatrix(t, tc.flags)
			ctx := codingAgentCtx(t)

			probe, err := service.CheckMemoryEnabled(ctx, int64(user.ID), repository)
			require.NoError(t, err)
			assert.Equal(t, tc.want, probe, "probe result")

			// The gate is exercised indirectly via any memory operation. If the
			// probe says enabled, the gate must allow the call (no
			// ErrFeatureNotEnabled). If the probe says disabled, the gate must
			// reject with ErrFeatureNotEnabled.
			err = service.CreateMemory(ctx, memory, repository)
			if tc.want {
				assert.NotErrorIs(t, err, core.ErrFeatureNotEnabled,
					"probe said enabled but gate rejected with ErrFeatureNotEnabled")
			} else {
				assert.ErrorIs(t, err, core.ErrFeatureNotEnabled,
					"probe said disabled but gate did not reject with ErrFeatureNotEnabled")
			}
		})
	}
}

func TestCheckMemoryEnabled_AgreesWithGateForUserActorOverride(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)
	memory := testMemory(repoNWO, user)
	memoryStore := &MockMemoryStore{
		SaveForRepositoryFunc: func(repoID core.RepositoryID, m *core.Memory) error {
			return nil
		},
	}
	ffClient := &actorAwareFeatureFlagClient{
		userOrRepoOrOwner: map[string]map[int64]bool{
			"copilot-feature-agentic-memory": {
				int64(user.ID): true,
			},
		},
	}
	service := core.NewMemoryService(memoryStore, ffClient, secretScanner, observability.NewNoopExporters(), &MockMemoryEnablementChecker{Enabled: true}, nil)
	ctx := codingAgentCtx(t)

	probe, err := service.CheckMemoryEnabled(ctx, int64(user.ID), repository)
	require.NoError(t, err)
	assert.True(t, probe, "probe must honor user actor overrides")

	err = service.CreateMemory(ctx, memory, repository)
	assert.NotErrorIs(t, err, core.ErrFeatureNotEnabled, "gate must honor the same user actor override")
}

type actorAwareFeatureFlagClient struct {
	flags             map[string]bool
	userOrRepoOrOwner map[string]map[int64]bool
}

func (c *actorAwareFeatureFlagClient) IsEnabled(ctx context.Context, featureFlagName string, actors ...vexi.Actor) bool {
	return c.flags[featureFlagName]
}

func (c *actorAwareFeatureFlagClient) IsEnabledForUser(ctx context.Context, featureFlagName string, userID int64) bool {
	return c.IsEnabled(ctx, featureFlagName)
}

func (c *actorAwareFeatureFlagClient) IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool {
	return c.IsEnabled(ctx, featureFlagName)
}

func (c *actorAwareFeatureFlagClient) IsEnabledForUserOrRepo(ctx context.Context, featureFlagName string, userID, repoID int64) bool {
	return c.IsEnabled(ctx, featureFlagName)
}

func (c *actorAwareFeatureFlagClient) IsEnabledForOrganization(ctx context.Context, featureFlagName string, orgID int64) bool {
	return c.IsEnabled(ctx, featureFlagName)
}

func (c *actorAwareFeatureFlagClient) IsEnabledForOwner(ctx context.Context, featureFlagName string, ownerID int64) bool {
	return c.IsEnabled(ctx, featureFlagName)
}

func (c *actorAwareFeatureFlagClient) IsEnabledForRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.Repository) bool {
	return c.IsEnabled(ctx, featureFlagName)
}
func (c *actorAwareFeatureFlagClient) IsEnabledForRepoOrOwnerWithDefaultValue(ctx context.Context, featureFlagName string, _ bool, actors sweagentd.Repository) bool {
	return c.IsEnabledForRepoOrOwner(ctx, featureFlagName, actors)
}

func (c *actorAwareFeatureFlagClient) IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.RepositoryWithActor) bool {
	if c.IsEnabled(ctx, featureFlagName) {
		return true
	}
	return c.userOrRepoOrOwner[featureFlagName][actors.GetActorID()]
}

func (c *actorAwareFeatureFlagClient) IsEnabledForGitHubApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return c.IsEnabled(ctx, featureFlagName)
}

func (c *actorAwareFeatureFlagClient) IsEnabledForOAuthApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return c.IsEnabled(ctx, featureFlagName)
}
