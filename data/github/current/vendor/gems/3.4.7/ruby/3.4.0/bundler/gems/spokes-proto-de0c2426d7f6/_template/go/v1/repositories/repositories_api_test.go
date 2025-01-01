package repositories

import (
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/require"
)

func TestListAvailableReplicasRequestValidate(t *testing.T) {
	req := &ListAvailableReplicasRequest{}
	require.Error(t, req.Validate())

	req = &ListAvailableReplicasRequest{Repository: types.NewRepository(1)}
	require.NoError(t, req.Validate())
}
