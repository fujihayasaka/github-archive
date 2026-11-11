package oidc

import (
	"testing"

	"github.com/github/sweagentd/internal/sweagentd"
)

func TestBuildSubject(t *testing.T) {
	tests := []struct {
		name           string
		opts           SubjectOptions
		params         TokenParams
		expectedSub    string
		expectedActSub string
	}{
		{
			name:           "default includes user_id when actor present",
			opts:           SubjectOptions{},
			params:         TokenParams{ActorID: 42, Actor: "octocat", OwnerID: 100, PlatformClientID: "Iv1.platform"},
			expectedSub:    "user_id:42",
			expectedActSub: "client_id:Iv1.platform:owner_id:user_id:100",
		},
		{
			name:           "agentOnlySubject true uses platform identity for sub",
			opts:           SubjectOptions{AgentOnlySubject: true},
			params:         TokenParams{ActorID: 42, Actor: "octocat", OwnerID: 100, PlatformClientID: "Iv1.platform", AppClientID: "Iv1.agent"},
			expectedSub:    "client_id:Iv1.platform:owner_id:user_id:100",
			expectedActSub: "client_id:Iv1.platform:owner_id:user_id:100",
		},
		{
			name:           "agentOnlySubject true with useAgentIdentity uses agent client_id for sub",
			opts:           SubjectOptions{AgentOnlySubject: true, UseAgenticAppIdentity: true},
			params:         TokenParams{ActorID: 42, Actor: "octocat", OwnerID: 100, OwnerType: sweagentd.OwnerTypeOrganization, PlatformClientID: "Iv1.platform", AppClientID: "Iv1.agent"},
			expectedSub:    "client_id:Iv1.agent:owner_id:org_id:100",
			expectedActSub: "client_id:Iv1.agent:owner_id:org_id:100",
		},
		{
			name:           "agentOnlySubject true with installation_id and useAgentIdentity",
			opts:           SubjectOptions{AgentOnlySubject: true, UseAgenticAppIdentity: true},
			params:         TokenParams{ActorID: 42, Actor: "octocat", OwnerID: 100, AppInstallationID: 76586, PlatformClientID: "Iv1.platform", AppClientID: "Iv1.agent"},
			expectedSub:    "installation_id:76586",
			expectedActSub: "installation_id:76586",
		},
		{
			name:           "zero actor_id falls back to platform identity",
			opts:           SubjectOptions{},
			params:         TokenParams{OwnerID: 100, PlatformClientID: "Iv1.platform"},
			expectedSub:    "client_id:Iv1.platform:owner_id:user_id:100",
			expectedActSub: "client_id:Iv1.platform:owner_id:user_id:100",
		},
		{
			name:           "agent actor falls back to platform identity with org",
			opts:           SubjectOptions{},
			params:         TokenParams{ActorID: 100, Actor: "copilot-swe-agent[agent]", ActorType: "bot", OwnerID: 200, OwnerType: sweagentd.OwnerTypeOrganization, PlatformClientID: "Iv1.platform", AppClientID: "Iv1.agent"},
			expectedSub:    "client_id:Iv1.platform:owner_id:org_id:200",
			expectedActSub: "client_id:Iv1.platform:owner_id:org_id:200",
		},
		{
			name:           "repoOnlySubject sets sub to repo identity with client_id",
			opts:           SubjectOptions{RepoOnlySubject: true},
			params:         TokenParams{ActorID: 42, Actor: "octocat", RepoID: 999, OwnerID: 100, PlatformClientID: "Iv1.platform"},
			expectedSub:    "client_id:Iv1.platform:repository_id:999",
			expectedActSub: "client_id:Iv1.platform:owner_id:user_id:100",
		},
		{
			name:           "repoOnlySubject with installation_id uses installation_id prefix",
			opts:           SubjectOptions{RepoOnlySubject: true, UseAgenticAppIdentity: true},
			params:         TokenParams{ActorID: 42, Actor: "octocat", RepoID: 999, OwnerID: 100, AppInstallationID: 555, PlatformClientID: "Iv1.platform", AppClientID: "Iv1.agent"},
			expectedSub:    "installation_id:555:repository_id:999",
			expectedActSub: "installation_id:555",
		},
		{
			name:           "agent name and version in act.sub",
			opts:           SubjectOptions{AgentOnlySubject: true, UseAgenticAppIdentity: true},
			params:         TokenParams{ActorID: 42, Actor: "octocat", OwnerID: 100, RepoID: 777, AppInstallationID: 555, CustomAgentName: "my-agent", CustomAgentVersion: "v1.2.3"},
			expectedSub:    "installation_id:555",
			expectedActSub: "installation_id:555:custom_agent:777:my-agent@v1.2.3",
		},
		{
			name:           "agent name without version uses latest",
			opts:           SubjectOptions{AgentOnlySubject: true, UseAgenticAppIdentity: true},
			params:         TokenParams{ActorID: 42, Actor: "octocat", OwnerID: 100, RepoID: 777, PlatformClientID: "Iv1.platform", AppClientID: "Iv1.agent", CustomAgentName: "my-agent"},
			expectedSub:    "client_id:Iv1.agent:owner_id:user_id:100",
			expectedActSub: "client_id:Iv1.agent:owner_id:user_id:100:custom_agent:777:my-agent@latest",
		},
		{
			name:           "no agent name omits agent suffix from act.sub",
			opts:           SubjectOptions{UseAgenticAppIdentity: true},
			params:         TokenParams{ActorID: 42, Actor: "octocat", OwnerID: 100, PlatformClientID: "Iv1.platform", AppClientID: "Iv1.agent"},
			expectedSub:    "user_id:42",
			expectedActSub: "client_id:Iv1.agent:owner_id:user_id:100",
		},
		{
			name:           "fallback to AppClientID when PlatformClientID empty",
			opts:           SubjectOptions{},
			params:         TokenParams{OwnerID: 100, AppClientID: "Iv1.abc"},
			expectedSub:    "client_id:Iv1.abc:owner_id:user_id:100",
			expectedActSub: "client_id:Iv1.abc:owner_id:user_id:100",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotSub, gotActSub := BuildSubject(tt.opts, tt.params)
			if gotSub != tt.expectedSub {
				t.Errorf("BuildSubject() sub = %q, want %q", gotSub, tt.expectedSub)
			}
			if gotActSub != tt.expectedActSub {
				t.Errorf("BuildSubject() actSub = %q, want %q", gotActSub, tt.expectedActSub)
			}
		})
	}
}
