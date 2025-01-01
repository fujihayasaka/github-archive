package hmac

import (
	"context"

	"github.com/github/launch/auth"
)

type KeyFetcher interface {
	GetHMACKeys(ctx context.Context) ([2]auth.Key, error)
}
