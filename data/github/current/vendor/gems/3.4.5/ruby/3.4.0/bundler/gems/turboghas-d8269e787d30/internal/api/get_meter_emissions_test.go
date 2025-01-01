package api_test

import (
	"context"
	"testing"
	"time"

	billingplatformv1 "github.com/github/hydro-schemas-go/hydro/schemas/billingplatform/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/billingplatform/v1/entities"

	"github.com/github/turboghas/internal/api"
	"github.com/github/turboghas/internal/dbtest"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/proto"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestGetMeterEmissions(t *testing.T) {
	db := dbtest.Seed(t, &billingplatformv1.Usage{
		UsageAt:  timestamppb.Now(),
		Quantity: 1,
		Sku:      "ghas_seats",
		Entity: &entities.EntityDetail{
			CustomerId: 1,
			ActorId:    1,
		},
	}, &billingplatformv1.Usage{
		UsageAt:  timestamppb.Now(),
		Quantity: 1,
		Sku:      "ghas_seats",
		Entity: &entities.EntityDetail{
			CustomerId: 1,
			// there are no tg_contributions in the seed for a user with ID 10, so this will count as the user 10 needing to be removed to make
			// the billing state consistent
			ActorId: 10,
		},
	})

	handler := api.New(dbtest.Dual(db))

	ctx := t.Context()

	replay(t, "get-meter-emissions", handler)

	advancedSecurityAPI := api.NewAdvancedSecurityAPI(db)

	activeCommittersResp, err := advancedSecurityAPI.GetActiveCommitters(ctx, &proto.GetActiveCommittersRequest{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
	})
	require.NoError(t, err)
	require.NotEmpty(t, activeCommittersResp.Users)

	meterEmissionsResp, err := advancedSecurityAPI.GetMeterEmissions(ctx, &proto.GetMeterEmissionsRequest{
		CustomerId: 1,
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
		Sku:        v1.SKU_SKU_GHAS_SEATS,
	})
	require.NoError(t, err)
	require.NotEmpty(t, meterEmissionsResp.Added)
	require.Subset(t, api.Map(activeCommittersResp.Users, func(u *proto.GetActiveCommittersResponse_User) uint64 {
		return u.Id
	}), meterEmissionsResp.Added)
}

func TestGetMeterEmissionsHighWatermark(t *testing.T) {
	now := time.Now()

	db := dbtest.Seed(t, &billingplatformv1.Usage{
		UsageAt:  timestamppb.New(now.Add(-1 * time.Hour)),
		Quantity: 1,
		Sku:      "ghas_licenses",
		Entity: &entities.EntityDetail{
			CustomerId: 1,
			ActorId:    1,
		},
	}, &billingplatformv1.Usage{
		UsageAt:  timestamppb.New(now.Add(-72 * time.Hour)),
		Quantity: 1,
		Sku:      "ghas_licenses",
		Entity: &entities.EntityDetail{
			CustomerId: 1,
			// add an emission that was made before the current billing period
			// this should not be emitted as user 2 is not an active committer
			ActorId: 2,
		},
	}, &billingplatformv1.Usage{
		UsageAt:  timestamppb.New(now.Add(-24 * time.Hour)),
		Quantity: 1,
		Sku:      "ghas_licenses",
		Entity: &entities.EntityDetail{
			CustomerId: 1,
			// there are no tg_contributions in the seed for a user with ID 10 but user 10 will be added because
			// this emission was made yesterday during the high watermark period
			ActorId: 10,
		},
	})

	handler := api.New(dbtest.Dual(db), twirp.WithServerInterceptors(func(fn twirp.Method) twirp.Method {
		return func(ctx context.Context, request any) (any, error) {
			if m, ok := request.(*proto.GetMeterEmissionsRequest); ok && m.CurrentBillingPeriodStartedAt != nil {
				m.CurrentBillingPeriodStartedAt = timestamppb.New(now.Add(-48 * time.Hour))
			}
			return fn(ctx, request)
		}
	}))

	replay(t, "get-meter-emissions-high-watermark", handler)
}

func TestGetMeterEmissionsWithAdditionalUsers(t *testing.T) {
	db := dbtest.Seed(t, &billingplatformv1.Usage{
		UsageAt:  timestamppb.Now(),
		Quantity: 1,
		Sku:      "ghas_seats",
		Entity: &entities.EntityDetail{
			CustomerId: 1,
			ActorId:    1,
		},
	})

	handler := api.New(dbtest.Dual(db))

	ctx := t.Context()

	replay(t, "get-meter-emissions-with-additional-users", handler)

	advancedSecurityAPI := api.NewAdvancedSecurityAPI(db)

	activeCommittersResp, err := advancedSecurityAPI.GetActiveCommitters(ctx, &proto.GetActiveCommittersRequest{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
	})
	require.NoError(t, err)
	require.NotEmpty(t, activeCommittersResp.Users)

	// there are no contributions for user 10
	// we are simulating GHES usage that is being provided by dotcom and they should be added
	meterEmissionsResp, err := advancedSecurityAPI.GetMeterEmissions(ctx, &proto.GetMeterEmissionsRequest{
		CustomerId:        1,
		EntityType:        v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:          1,
		AdditionalUserIds: []uint64{10},
		Sku:               v1.SKU_SKU_GHAS_SEATS,
	})
	require.NoError(t, err)
	require.NotEmpty(t, meterEmissionsResp.Added)
	require.Contains(t, meterEmissionsResp.Added, uint64(10))
}
