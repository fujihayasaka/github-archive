package jobs

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestResolveAction(t *testing.T) {
	tests := []struct {
		name     string
		hasPR    bool
		headRef  string
		expected AgentAction
	}{
		{
			name:     "pre-existing PR with HeadRef returns fix-pr-comment",
			hasPR:    true,
			headRef:  "my-feature-branch",
			expected: AgentActionFixPRComment,
		},
		{
			name:     "PR without HeadRef returns fix",
			hasPR:    true,
			headRef:  "",
			expected: AgentActionFix,
		},
		{
			name:     "no PR returns task",
			hasPR:    false,
			headRef:  "",
			expected: AgentActionTask,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ResolveAction(tt.hasPR, tt.headRef)
			require.Equal(t, tt.expected, result)
		})
	}
}
