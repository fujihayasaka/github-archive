package sandbox

import (
	launchsandbox "github.com/github/launch/services/pb/sandbox"
)

// LifecycleParams controls sandbox auto-suspend and auto-delete behavior.
type LifecycleParams struct {
	AutoSuspendEnabled        bool
	AutoSuspendIdleTimeoutMin int32
	SuspendMode               string // "Memory" or "Disk"
	AutoDeleteAfterMin        int32  // minutes after the sandbox is suspended
}

func (s *Service) buildLifecyclePolicy(params *CreateSandboxParams) *launchsandbox.LifecyclePolicy {
	if params.Lifecycle == nil {
		return &launchsandbox.LifecyclePolicy{
			AutoSuspend: &launchsandbox.AutoSuspendPolicy{
				Enabled: false,
			},
		}
	}

	lc := params.Lifecycle
	policy := &launchsandbox.LifecyclePolicy{
		AutoSuspend: &launchsandbox.AutoSuspendPolicy{
			Enabled:     lc.AutoSuspendEnabled,
			SuspendMode: lc.SuspendMode,
		},
	}
	if lc.AutoSuspendIdleTimeoutMin > 0 {
		policy.AutoSuspend.IdleTimeout = lc.AutoSuspendIdleTimeoutMin
	}
	if lc.AutoDeleteAfterMin > 0 {
		policy.AutoDelete = &launchsandbox.AutoDeletePolicy{
			DeleteAfter: lc.AutoDeleteAfterMin,
		}
	}
	return policy
}
