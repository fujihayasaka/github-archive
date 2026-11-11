package maintenance

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

var (
	// Request data
	repository = types.NewRepository(1)
	reqCtx     = types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE)
)

func TestNewMaintenanceInfoRequest(t *testing.T) {
	req := NewMaintenanceInfoRequest(reqCtx, repository)
	require.Equal(t, req, &MaintenanceInfoRequest{
		RequestContext: reqCtx,
		Repository:     repository,
	})
}

func TestMaintenanceInfoRequestValidate(t *testing.T) {
	tests := []struct {
		name string
		req  *MaintenanceInfoRequest
	}{
		{
			"valid",
			NewMaintenanceInfoRequest(reqCtx, repository),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.NoError(t, tt.req.Validate())
		})
	}
}

func TestMaintenanceInfoRequestValidateErrors(t *testing.T) {
	tests := []struct {
		name string
		req  *MaintenanceInfoRequest
		err  string
	}{
		{
			"empty",
			&MaintenanceInfoRequest{},
			"twirp error invalid_argument: repository is required",
		},
		{
			"missing repository",
			&MaintenanceInfoRequest{RequestContext: reqCtx},
			"twirp error invalid_argument: repository is required",
		},
		{
			"invalid repository",
			&MaintenanceInfoRequest{RequestContext: reqCtx, Repository: &types.Repository{Type: types.Repository_TYPE_REPOSITORY, Id: 0}},
			"twirp error invalid_argument: repository.id is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.err, tt.req.Validate().Error())
		})
	}
}
