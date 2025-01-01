package resource

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func createTestProtectedBranch() *protectedBranch {
	return &protectedBranch{
		baseHandler: baseHandler{log.NewNullLogger()},
		pb: &v1.ProtectedBranch{
			ResourceId:           "protectedbranch-master-http//gh.io/guacamole-bowl/vim",
			RepositoryResourceId: "http://gh.io/guacamole-bowl/vim",
			Name:                 "master",
			RequiresApprovingReviews: &wrapperspb.BoolValue{
				Value: false,
			},
			RequiredApprovingReviewCount: &wrapperspb.Int32Value{
				Value: 0,
			},
			RequiresCommitSignatures: &wrapperspb.BoolValue{
				Value: false,
			},
			RequiresLinearHistory: &wrapperspb.BoolValue{
				Value: false,
			},
			AllowsForcePushes: &wrapperspb.BoolValue{
				Value: false,
			},
			AllowsDeletions: &wrapperspb.BoolValue{
				Value: false,
			},
			IsAdminEnforced: &wrapperspb.BoolValue{
				Value: false,
			},
			RequiresStatusChecks: &wrapperspb.BoolValue{
				Value: false,
			},
			RequiresStrictStatusChecks: &wrapperspb.BoolValue{
				Value: false,
			},
			RequiresCodeOwnerReviews: &wrapperspb.BoolValue{
				Value: false,
			},
			DismissesStaleReviews: &wrapperspb.BoolValue{
				Value: false,
			},
			RestrictsReviewDismissals: &wrapperspb.BoolValue{
				Value: false,
			},
			RestrictsPushes: &wrapperspb.BoolValue{
				Value: false,
			},
			RequiredStatusCheckContexts: []string{},
			RequiresReviewThreadResolution: &wrapperspb.BoolValue{
				Value: false,
			},
			RequireLastPushApproval: &wrapperspb.BoolValue{
				Value: false,
			},
		},
	}
}

func Test_protected_branch_deps(t *testing.T) {
	b := createTestProtectedBranch()
	deps, err := b.dependencies()
	require.NoError(t, err)
	expected := newTransformedDeps()
	expected.int64Deps.Add(b.pb.RepositoryResourceId)
	require.Equal(t, expected, deps)
}

func Test_protected_branch_load(t *testing.T) {
	b := createTestProtectedBranch()
	resolved := resolvedIDsByResource{
		"http://gh.io/guacamole-bowl/vim": {int64Val: 1},
	}
	importer := client.NewDummyImporter(log.NewNullLogger())
	err := b.load(context.Background(), importer, resolved)
	require.NoError(t, err)
	res := b.newResolvedIDs()
	require.Equal(t, resolvedIDsByResource{
		b.pb.ResourceId: {int64Val: b.importedResult.ProtectedBranch.Id},
	}, res)
}
