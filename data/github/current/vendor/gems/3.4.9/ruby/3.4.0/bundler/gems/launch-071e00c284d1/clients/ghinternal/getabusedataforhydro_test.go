package ghinternal

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/apphttp"
)

func TestGhclient_GetAbuseDataForHydro(t *testing.T) {

	businessOwnedRepoEntityID := "MDEwOlJlcG9zaXRvcnk2MQ=="
	businessEntityID := "MDEwOkVudGVycHJpc2UxNg=="
	businessID := 16

	userEntityID := "MDQ6VXNlcjE1Ng=="
	userID := 156

	// Organization 67336198
	orgID := 67336198
	orgNextID := "O_kgDOBAN4Bg"
	orgLegacyID := "MDEyOk9yZ2FuaXphdGlvbjY3MzM2MTk4"

	// User 16631042
	userDatabaseID := 16631042
	userNextID := "U_kgDOAP3FAg"
	userLegacyID := "MDQ6VXNlcjE2NjMxMDQy"

	hdl := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		require.Equal(t, r.URL.Path, "/internal/actions/abuse-batch-info")
		var input struct {
			Ids []string
		}
		err := json.NewDecoder(r.Body).Decode(&input)
		require.NoError(t, err)
		fmt.Fprintf(w, `{
			"owners_by_id": {
				%q: {
					"id": %q,
					"database_id": %d,
					"plan_name": "free",
					"name": "user-owner",
					"type": "User"
				},
				%q: {
					"id": %q,
					"database_id": %d,
					"plan_name": "enterprise",
					"name": "pandas-pancakes",
					"type": "Business"
				},
				"MDEwOlJlcG9zaXRvcnk2Mg==": {
					"id": "MDQ6VXNlcjE1Ng==",
					"database_id": %d,
					"plan_name": "free",
					"name": "user-owner",
					"type": "User"
				},
				"MDEwOlJlcG9zaXRvcnk2Mw==": {
					"id": "MDEyOk9yZ2FuaXphdGlvbjE1OA==",
					"database_id": 158,
					"plan_name": "silver",
					"name": "org-owner",
					"type": "Organization"
				},
				"MDEwOkVudGVycHJpc2UxNg==": {
					"id": "MDEwOkVudGVycHJpc2UxNg==",
					"database_id": 16,
					"plan_name": "enterprise",
					"name": "pandas-pancakes",
					"type": "Business"
				},
				%q: {
					"id": %q,
					"plan_name": "enterprise",
					"database_id": %d,
					"name": "bbq-dinos",
					"type": "Organization"
				},
				%q: {
					"id": %q,
					"database_id": %d,
					"plan_name": "free",
					"name": "user-owner",
					"type": "User"
				}
			}
		}`, userEntityID, userEntityID, userID, businessOwnedRepoEntityID, businessEntityID, businessID, userID, orgLegacyID, orgLegacyID, orgID, userNextID, userNextID, userDatabaseID)
	})

	entityIDs := []types.GlobalID{
		types.GlobalID(userEntityID),
		types.GlobalID(businessOwnedRepoEntityID),
		"MDEwOlJlcG9zaXRvcnk2Mg==",
		"MDEwOlJlcG9zaXRvcnk2Mw==",
		"MDEwOkVudGVycHJpc2UxNg==",
		types.GlobalID(orgNextID),    // Next ID input, response will return the legacy ID
		types.GlobalID(userLegacyID), // Legacy ID input, response will only reference the next ID
	}
	_, url, teardown := newRemoteServer(hdl)
	defer teardown()

	obs := observability.NewNullObservability()
	c := New(
		url,
		apphttp.NewClient(),
		obs,
		WithRequestOptions(WithHMAC([]byte("hi"))),
	)
	res, err := c.GetAbuseDataForHydro(context.Background(), entityIDs)
	require.NoError(t, err)

	assert.Equal(t, &hydroV0.BillingPlanOwner{
		GlobalId:   userEntityID,
		DatabaseId: int64(userID),
		Name:       "user-owner",
		PlanSku:    hydroV0.BillingPlanOwner_SKU_FREE,
		Type:       hydroV0.BillingPlanOwner_TYPE_USER,
	}, res.OwnersByEntityID[types.GlobalID(userEntityID)])
	assert.Equal(t, &hydroV0.BillingPlanOwner{
		GlobalId:   businessEntityID,
		DatabaseId: int64(businessID),
		Name:       "pandas-pancakes",
		PlanSku:    hydroV0.BillingPlanOwner_SKU_ENTERPRISE,
		Type:       hydroV0.BillingPlanOwner_TYPE_BUSINESS,
	}, res.OwnersByEntityID[types.GlobalID(businessOwnedRepoEntityID)], "should handle cases where entity ID does not equal billing entityID")
	assert.Equal(t, &hydroV0.BillingPlanOwner{
		GlobalId:   "MDEwOkVudGVycHJpc2UxNg==",
		DatabaseId: int64(16),
		Name:       "pandas-pancakes",
		PlanSku:    hydroV0.BillingPlanOwner_SKU_ENTERPRISE,
		Type:       hydroV0.BillingPlanOwner_TYPE_BUSINESS,
	}, res.OwnersByEntityID["MDEwOkVudGVycHJpc2UxNg=="])
	assert.Equal(t, &hydroV0.BillingPlanOwner{
		GlobalId:   orgLegacyID,
		DatabaseId: int64(orgID),
		Name:       "bbq-dinos",
		PlanSku:    hydroV0.BillingPlanOwner_SKU_ENTERPRISE,
		Type:       hydroV0.BillingPlanOwner_TYPE_ORGANIZATION,
	}, res.OwnersByEntityID[types.GlobalID(orgNextID)], "should handle mapping next IDs to legacy IDs")
	assert.Equal(t, &hydroV0.BillingPlanOwner{
		GlobalId:   userNextID,
		DatabaseId: int64(userDatabaseID),
		Name:       "user-owner",
		PlanSku:    hydroV0.BillingPlanOwner_SKU_FREE,
		Type:       hydroV0.BillingPlanOwner_TYPE_USER,
	}, res.OwnersByEntityID[types.GlobalID(userLegacyID)], "should preserve the format of the original entity ID")
	assert.Len(t, res.OwnersByEntityID, 7)
}
