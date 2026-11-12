package experimental

import (
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/stretchr/testify/require"
)

var (
	repository = types.NewRepository(1)

	sel1 = selectors.NewObjectSelectorByTreeishAndPath(
		types.NewTreeishWithObjectID(types.NewObjectID("1234567890123456789012345678901234567890")),
		types.NewPath([]byte("a/b/c")),
		nil,
	)

	sel2 = selectors.NewObjectSelectorByTreeishAndPath(
		types.NewTreeishWithReference(types.DefaultBranch()),
		types.NewPath([]byte("d/e/f")),
		nil,
	)

	reqCtx = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
)

func TestNewExperimentalResolveObjectsRequest(t *testing.T) {
	batches := []*ObjectSelectorsByRepo{}
	batches = append(batches, NewObjectSelectorsByRepo(repository, sel1, sel2))
	req := NewResolveObjectsRequest(reqCtx, batches...)

	require.Equal(t, &ResolveObjectsRequest{
		RequestContext:        reqCtx,
		ObjectSelectorsByRepo: batches,
	},
		req)
}

func TestExperimentalResolveObjectsRequestErrors(t *testing.T) {
	tests := []struct {
		name string
		req  *ResolveObjectsRequest
		err  string
	}{
		{
			"empty",
			&ResolveObjectsRequest{},
			"twirp error invalid_argument: ObjectSelectorsByRepo is required",
		},
		{
			"ObjectSelectorsByRepo batch missing repository",
			NewResolveObjectsRequest(reqCtx, NewObjectSelectorsByRepo(nil, sel1)),
			"twirp error invalid_argument: repository cannot be empty @ ObjectSelectorsByRepo[0]",
		},
		{
			"ObjectSelectorsByRepo batch contains invalid repo",
			NewResolveObjectsRequest(reqCtx, NewObjectSelectorsByRepo(&types.Repository{}, sel1)),
			"twirp error invalid_argument: invalid repository @ ObjectSelectorsByRepo[0] repository.id is required",
		},
		{
			"ObjectSelectorsByRepo batch contains no selectors",
			NewResolveObjectsRequest(reqCtx, NewObjectSelectorsByRepo(repository)),
			"twirp error invalid_argument: selectors cannot be empty @ ObjectSelectorsByRepo[0]",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			require.EqualError(t, test.req.Validate(), test.err)
		})
	}
}
