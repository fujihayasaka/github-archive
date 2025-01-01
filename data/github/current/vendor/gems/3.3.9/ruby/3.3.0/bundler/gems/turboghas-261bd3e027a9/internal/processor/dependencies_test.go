package processor_test

import (
	"context"
	"testing"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/mocks"
	"github.com/github/turboghas/internal/processor"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

type mockDeps struct {
	mock.Mock
}

func (m *mockDeps) GetEmailsFromRefUpdates(ctx context.Context, repositoryID uint64, refUpdates []*githubv1.PostReceive_RefUpdate) ([]*commits.Contributor, error) {
	args := m.Called(ctx, repositoryID, refUpdates)
	return args.Get(0).([]*commits.Contributor), args.Error(1)
}

func (m *mockDeps) Enqueue(ctx context.Context, msg proto.Message) error {
	args := m.Called(ctx, msg)
	return args.Error(0)
}

type mockSpokes struct {
	mock.Mock
}

func (m *mockSpokes) ListContributors(ctx context.Context, request *commits.ListContributorsRequest) (*commits.ListContributorsResponse, error) {
	args := m.Called(ctx, request)
	return args.Get(0).(*commits.ListContributorsResponse), args.Error(1)
}

func TestIsEntityTooLarge(t *testing.T) {
	t.Run("test business", func(t *testing.T) {
		f := mocks.Cleanup(t, &mocks.Flipper{})
		f.On("IsEnabled", mocks.IsContext, "turboghas_entity_too_large", "Business:1").Return(true, nil).Once()

		ok, err := processor.IsEntityTooLarge(fromctx.Flipper.With(context.Background(), f), data.PtrTo(uint64(1)), 2, 1)
		require.NoError(t, err)
		require.True(t, ok)
	})

	t.Run("test user", func(t *testing.T) {
		f := mocks.Cleanup(t, &mocks.Flipper{})
		f.On("IsEnabled", mocks.IsContext, "turboghas_entity_too_large", "User:1").Return(true, nil).Once()

		ok, err := processor.IsEntityTooLarge(fromctx.Flipper.With(context.Background(), f), nil, 1, 1)
		require.NoError(t, err)
		require.True(t, ok)
	})

	t.Run("test repository", func(t *testing.T) {
		f := mocks.Cleanup(t, &mocks.Flipper{})
		f.On("IsEnabled", mocks.IsContext, "turboghas_entity_too_large", "User:1").Return(false, nil).Once()
		f.On("IsEnabled", mocks.IsContext, "turboghas_entity_too_large", "Repository:1").Return(true, nil).Once()

		ok, err := processor.IsEntityTooLarge(fromctx.Flipper.With(context.Background(), f), nil, 1, 1)
		require.NoError(t, err)
		require.True(t, ok)
	})

	t.Run("test enterprise", func(t *testing.T) {
		f := mocks.Cleanup(t, &mocks.Flipper{})

		ok, err := processor.IsEntityTooLarge(fromctx.Env.With(fromctx.Flipper.With(context.Background(), f), "enterprise"), nil, 1, 1)
		require.NoError(t, err)
		require.False(t, ok)
	})
}

func TestGetEmailsFromRefUpdates(t *testing.T) {
	spokes := mocks.Cleanup(t, &mockSpokes{})
	spokes.On("ListContributors", mocks.IsContext, &commits.ListContributorsRequest{
		Repository: &types.Repository{
			Id:   1,
			Type: types.Repository_TYPE_REPOSITORY,
		},
		RequestContext: &types.RequestContext{
			// prefer to give up quickly if a repository is hitting internal rate limits
			// rather than adding more load to gitrpcd
			QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
		},
		Selector: &commits.ListContributorsRequest_PushSelector{
			PushSelector: &selectors.PushSelector{
				ReferenceUpdates: []*types.ReferenceUpdate{{
					Before: &types.ObjectID{
						Id: "previous",
					},
					After: &types.ObjectID{
						Id: "current",
					},
					Reference: &types.Reference{
						Name: []byte("test"),
					},
				}},
			},
		},
	}).Return(&commits.ListContributorsResponse{
		Contributors: []*commits.Contributor{
			// deduplicated by email
			{EmailBytes: []byte("test@test.com"), CommitOid: &types.ObjectID{Id: "4d39ee7d0836ac8c17a662685db03a85fa845a40"}},
			{EmailBytes: []byte("test@test.com"), CommitOid: &types.ObjectID{Id: "4d39ee7d0836ac8c17a662685db03a85fa845a4f"}},
		},
	}, nil)
	deps := processor.NewDependencies(spokes)
	emails, err := deps.GetEmailsFromRefUpdates(context.Background(), 1, []*githubv1.PostReceive_RefUpdate{
		{RefName: "test", PreviousRefOid: "previous", CurrentRefOid: "current"},
	})
	require.NoError(t, err)
	require.Equal(t, []*commits.Contributor{
		{EmailBytes: []byte("test@test.com"), CommitOid: &types.ObjectID{Id: "4d39ee7d0836ac8c17a662685db03a85fa845a4f"}},
	}, emails)
}
