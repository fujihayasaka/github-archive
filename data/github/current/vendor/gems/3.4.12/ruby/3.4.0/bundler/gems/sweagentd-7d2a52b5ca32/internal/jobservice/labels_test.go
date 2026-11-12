package jobservice

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/require"
)

type ttActors struct {
	repoID  int64
	ownerID int64
	userID  int64
}

func (t ttActors) GetRepositoryID() int64 { return t.repoID }
func (t ttActors) GetOwnerID() int64      { return t.ownerID }
func (t ttActors) GetActorID() int64      { return t.userID }

func TestLabelMetadata(t *testing.T) {
	t.Run("captures labels in general", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents: false,
		})
		obsv := observability.NewNoopExporters()
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		s := New(obsv, ffClient, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", nil)

		issue := github.GQLIssue{
			GQLLabelable: github.GQLLabelable{
				Labels: github.GQLConnection[github.GQLLabel]{
					Nodes: []github.GQLLabel{
						{
							Name: sweagentd.CopilotLabelPrefix + "test-subagent",
						},
					},
				},
			},
		}
		lm := s.LabelMetadataWithChecks(context.Background(), issue, &ttActors{1, 1, 1})
		require.Len(t, lm.CopilotLabels, 1)
		require.Len(t, lm.Labels, 1)
	})
}
