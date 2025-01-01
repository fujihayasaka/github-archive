// Package deliveryguid provides helpers for interacting with a webhook delivery GUID.
package deliveryguid

import (
	"context"
	"time"

	"github.com/github/go-kvp"
	"github.com/google/uuid"
	"github.com/pkg/errors"

	"github.com/github/launch/observability/ctxstash"
)

// ExtractTime parses a string representing webhook delivery UUID and returns the time if valid.
func ExtractTime(deliveryGUID string) (time.Time, error) {
	uid, err := uuid.Parse(deliveryGUID)
	if err != nil {
		return time.Time{}, errors.Wrapf(err, "could not extract time for GUID %q", deliveryGUID)
	}
	sec, nsec := uid.Time().UnixTime()
	return time.Unix(sec, nsec), nil
}

// WithDeliveryGUID adds the given delivery GUID to the logging context.
func WithDeliveryGUID(ctx context.Context, deliveryGUID *string) context.Context {
	if deliveryGUID != nil {
		return ctxstash.WithFields(ctx, kvp.String("gh.launch.webhook_delivery_guid", *deliveryGUID))
	}
	return ctx
}
