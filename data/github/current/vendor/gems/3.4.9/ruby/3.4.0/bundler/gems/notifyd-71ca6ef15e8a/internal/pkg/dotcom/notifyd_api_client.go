// Package dotcom contains the notifyd API client.
package dotcom

import (
	context "context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-twirp/v2/client/auth"
	"github.com/github/go-twirp/v2/client/requestid"

	"github.com/github/notifyd/internal/pkg/http"
	"github.com/github/notifyd/internal/pkg/tenancy"
	notifyd "github.com/github/notifyd/proto/notifyd/v1"
)

// APIClient is a wrapper around notifyd.NotifydAPI but accepting the current tenant as an argument
// This indicates that we need to make sure the tenant is propagated in HTTP requests
type APIClient interface {
	CheckDeliverMobilePushPolicy(context.Context, tenancy.Tenant, *notifyd.CheckDeliverMobilePushPolicyRequest) (*notifyd.CheckDeliverMobilePushPolicyResponse, error)
	CheckDeliverEmailPolicy(context.Context, tenancy.Tenant, *notifyd.CheckDeliverEmailPolicyRequest) (*notifyd.CheckDeliverEmailPolicyResponse, error)
	BatchCheckNotifyPolicy(context.Context, tenancy.Tenant, *notifyd.BatchCheckNotifyPolicyRequest) (*notifyd.BatchCheckNotifyPolicyResponse, error)
	BatchCheckIgnoredRepository(context.Context, tenancy.Tenant, *notifyd.BatchCheckIgnoredRepositoryRequest) (*notifyd.BatchCheckIgnoredRepositoryResponse, error)
	PostProcessEmailContent(context.Context, tenancy.Tenant, *notifyd.PostProcessEmailContentRequest) (*notifyd.PostProcessEmailContentResponse, error)
	GetDeliverEmailData(context.Context, tenancy.Tenant, *notifyd.GetDeliverEmailDataRequest) (*notifyd.GetDeliverEmailDataResponse, error)
}

type client struct {
	twirp notifyd.NotifydAPI
}

func (c *client) CheckDeliverMobilePushPolicy(ctx context.Context, tenant tenancy.Tenant, req *notifyd.CheckDeliverMobilePushPolicyRequest) (*notifyd.CheckDeliverMobilePushPolicyResponse, error) {
	return c.twirp.CheckDeliverMobilePushPolicy(tenancy.ContextWithTenant(ctx, tenant), req)
}

func (c *client) CheckDeliverEmailPolicy(ctx context.Context, tenant tenancy.Tenant, req *notifyd.CheckDeliverEmailPolicyRequest) (*notifyd.CheckDeliverEmailPolicyResponse, error) {
	return c.twirp.CheckDeliverEmailPolicy(tenancy.ContextWithTenant(ctx, tenant), req)
}

func (c *client) BatchCheckNotifyPolicy(ctx context.Context, tenant tenancy.Tenant, req *notifyd.BatchCheckNotifyPolicyRequest) (*notifyd.BatchCheckNotifyPolicyResponse, error) {
	return c.twirp.BatchCheckNotifyPolicy(tenancy.ContextWithTenant(ctx, tenant), req)
}

func (c *client) BatchCheckIgnoredRepository(ctx context.Context, tenant tenancy.Tenant, req *notifyd.BatchCheckIgnoredRepositoryRequest) (*notifyd.BatchCheckIgnoredRepositoryResponse, error) {
	return c.twirp.BatchCheckIgnoredRepository(tenancy.ContextWithTenant(ctx, tenant), req)
}

func (c *client) PostProcessEmailContent(ctx context.Context, tenant tenancy.Tenant, req *notifyd.PostProcessEmailContentRequest) (*notifyd.PostProcessEmailContentResponse, error) {
	return c.twirp.PostProcessEmailContent(tenancy.ContextWithTenant(ctx, tenant), req)
}

func (c *client) GetDeliverEmailData(ctx context.Context, tenant tenancy.Tenant, req *notifyd.GetDeliverEmailDataRequest) (*notifyd.GetDeliverEmailDataResponse, error) {
	return c.twirp.GetDeliverEmailData(tenancy.ContextWithTenant(ctx, tenant), req)
}

// NewAPIClient creates a new APIClient
func NewAPIClient(url, key string, timeout time.Duration, logger log.Logger) (APIClient, error) {
	baseClient := http.NewClient(http.WithRetryTimeout(timeout), http.WithLogger(logger))
	requestIDClient := requestid.NewForwarder(baseClient)
	tenantClient := tenancy.NewForwarder(requestIDClient)
	twirpClient, err := auth.NewRequestHMACSigner(key, tenantClient)
	if err != nil {
		return nil, fmt.Errorf("initializing RequestHMACSigner: %w", err)
	}

	twirp := notifyd.NewNotifydAPIJSONClient(url, twirpClient)
	client := &client{twirp: twirp}

	return client, nil
}
