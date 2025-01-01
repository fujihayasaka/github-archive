package chatops

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/services/pb/deploy"
)

func Test_getGlobalIDOutput(t *testing.T) {

	op := getGlobalIDOutput(launchconfig.ProductionAppEnv.String(), &deploy.GetAZForGlobalIDChatopsResponse{
		AzTenantName: "az-tenant-name",
		AzTenantID:   "az-tenant-id",
		GlobalID:     "az-global-id",
	})
	assert.Equal(t, `:actions-service: Actions Service details for az-global-id in production:
*GlobalID* az-global-id
*Tenant Name* az-tenant-name
*Tenant Id* az-tenant-id
`, op)
}
