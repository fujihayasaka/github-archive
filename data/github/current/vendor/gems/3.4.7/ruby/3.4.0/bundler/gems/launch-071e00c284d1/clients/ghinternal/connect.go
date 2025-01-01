package ghinternal

import (
	"context"
	"net/http"
	"time"

	errs "github.com/pkg/errors"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types/errors"
)

// ErrConnectNotEnabled is used when dotcom refuses
// the GitHub Connect authenticated request
var ErrConnectNotEnabled = errs.New("GitHub Connect request is not permitted by dotcom")

// GetConnectToken fetches a GitHub Connect token and returns it.
func (c *ghclient) GetConnectToken(ctx context.Context) (*tokens.AccessToken, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	it := &tokens.ScopedInstallationToken{}

	err := c.do(ctx, "GetConnectToken", http.MethodPost, "enterprise/actions-token", nil, &it, func(res *http.Response) (bool, error) {
		switch res.StatusCode {
		// We handle both of these errors because we may want to change the 404 in
		// github/github to a 418 in the future and this allows us to roll forward
		// without breaking anything.
		case http.StatusNotFound, http.StatusPreconditionFailed:
			// permErr = ErrConnectNotEnabled
			return false, ErrConnectNotEnabled
		default:
			retryable := res.StatusCode >= 500
			if res.StatusCode >= 400 {
				return retryable, errors.NewHTTPError(res)
			}
		}
		return false, nil
	})
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	var expiration time.Time
	if it.ExpiresAt != nil {
		expiration = *it.ExpiresAt
	}

	return &tokens.AccessToken{
		Token:  it.Token,
		Expiry: expiration,
	}, nil
}
