package delivery_processor

import (
	"context"

	"github.com/github/turboscan/ts"
)

type DeliveryService interface {
	CreateDelivery(ctx context.Context, d *ts.Delivery) error
	NextDelivery(ctx context.Context, repositoryID ts.RepositoryEID) (*ts.Delivery, error)
	WithLockedDelivery(ctx context.Context, delivery *ts.Delivery, fn func(context.Context) error) error
	CompleteDelivery(ctx context.Context, d *ts.Delivery) error
}
