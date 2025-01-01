package api_test

import (
	"testing"

	billingplatformv1 "github.com/github/hydro-schemas-go/hydro/schemas/billingplatform/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/billingplatform/v1/entities"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/turboghas/internal/api"
	"github.com/github/turboghas/internal/dbtest"
)

func TestGetSummary(t *testing.T) {
	// simulate some GHES meter usage
	db := dbtest.Seed(t, &billingplatformv1.Usage{
		UsageAt:  timestamppb.Now(),
		Quantity: 1,
		Sku:      "ghas_seats",
		Entity: &entities.EntityDetail{
			CustomerId: 1,
			ActorId:    10,
		},
	})

	handler := api.New(dbtest.Dual(db))

	replay(t, "get-summary", handler)
}
