package backups

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/require"
	"testing"
)

var (
	reqCtx = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
)

func TestPerformRequestValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		req  *PerformBackupRequest
		err  string
	}{
		{
			"empty",
			&PerformBackupRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			NewPerformBackupRequest(reqCtx, nil, nil),
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			NewPerformBackupRequest(reqCtx, &types.Repository{
				Type: types.Repository_TYPE_REPOSITORY,
				Id:   0,
			}, nil),
			"twirp error invalid_argument: repository.id is required",
		},
		{
			"invalid parent repository",
			NewPerformBackupRequest(reqCtx, &types.Repository{
				Type: types.Repository_TYPE_REPOSITORY,
				Id: 2,
			}, &types.Repository{
				Type: types.Repository_TYPE_GIST,
				Id: 1,
			}),
			"twirp error invalid_argument: parent repository type must match target repository type",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.req.Validate(), tt.err)
		})
	}
}
