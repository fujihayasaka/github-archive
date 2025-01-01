package resource

import (
	"context"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/github/migrations-vnext/internal/pkg/set"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func createTestReactionsBatch(subject string, rs []*v1.Reaction) *reactionsBatch {
	return &reactionsBatch{
		baseHandler: baseHandler{
			log.NewNullLogger(),
		},
		pb: &v1.ReactionsBatch{
			ResourceId:        "reactions-batch-foo",
			SubjectResourceId: subject,
			SubjectType:       v1.ReactionSubjectType_REACTION_SUBJECT_TYPE_ISSUE,
			Reactions:         rs,
		},
	}
}

func TestReactionsBatchDependencies(t *testing.T) {
	user := "http://gh.io/monalisa"
	reactions := []*v1.Reaction{
		{
			UserResourceId: user,
		},
	}
	subject := "http://gh.io/guacamole-bowl/pulls/3"
	rb := createTestReactionsBatch(subject, reactions)
	deps, err := rb.dependencies()
	require.NoError(t, err)
	require.NotNil(t, deps)

	expected := &transformedDeps{
		int64Deps: set.FromSlice([]string{
			subject,
		}),
		strDeps: set.FromSlice([]string{
			reactions[0].UserResourceId,
		}),
	}
	require.Equal(t, expected, deps)

	t.Run("DependsOnMultipleUsers", func(t *testing.T) {
		user2 := "http://gh.io/monalisa2"
		reactions := []*v1.Reaction{
			{
				UserResourceId: user,
			},
			{
				UserResourceId: user2,
			},
		}
		rb := createTestReactionsBatch(subject, reactions)
		deps, err := rb.dependencies()
		require.NoError(t, err)
		require.NotNil(t, deps)

		expected := &transformedDeps{
			int64Deps: set.FromSlice([]string{
				subject,
			}),
			strDeps: set.FromSlice([]string{
				reactions[0].UserResourceId,
				reactions[1].UserResourceId,
			}),
		}
		require.Equal(t, expected, deps)
	})
	t.Run("DeduplicatesUserDependency", func(t *testing.T) {
		reactions := []*v1.Reaction{
			{
				UserResourceId: user,
			},
			{
				UserResourceId: user,
			},
		}
		rb := createTestReactionsBatch(subject, reactions)
		deps, err := rb.dependencies()
		require.NoError(t, err)
		require.NotNil(t, deps)

		expected := &transformedDeps{
			int64Deps: set.FromSlice([]string{
				subject,
			}),
			strDeps: set.FromSlice([]string{
				reactions[0].UserResourceId,
			}),
		}
		require.Equal(t, expected, deps)
	})
}

func TestReactionsBatchLoad(t *testing.T) {
	someTime := timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC))
	logger := log.NewNullLogger()
	importer := client.NewDummyImporter(logger)
	user := "http://gh.io/monalisa"
	reactions := []*v1.Reaction{
		{
			UserResourceId: user,
			Content:        "+1",
			CreatedAt:      someTime,
		},
	}
	subject := "http://gh.io/guacamole-bowl/pulls/3"
	rb := createTestReactionsBatch(subject, reactions)
	resolved := resolvedIDsByResource{
		subject: {int64Val: 1},
		user:    {strVal: "http://new.io/monalisa"},
	}
	err := rb.load(context.Background(), importer, resolved)
	require.NoError(t, err)
	require.Len(t, importer.Reactions, 1)

	require.Equal(t, &octov1.ImportReactionsRequest{
		SubjectType: octov1.ReactionSubjectType_REACTION_SUBJECT_TYPE_ISSUE,
		SubjectId:   1,
		Reactions: []*octov1.ReactionBatch{
			{
				UserLogin: "http://new.io/monalisa",
				Content:   octov1.ReactionContent_REACTION_CONTENT_THUMBS_UP,
				CreatedAt: someTime,
			},
		},
	}, importer.Reactions[0])
}
