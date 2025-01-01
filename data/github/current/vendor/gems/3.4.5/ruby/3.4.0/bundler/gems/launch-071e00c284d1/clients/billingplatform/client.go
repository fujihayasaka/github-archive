package billingplatform

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	billingplatform "github.com/github/actions-proto/gen/go/billing-platform/api/v1"
	billingplatformbase "github.com/github/actions-proto/gen/go/billing-platform/base/v1"
	"github.com/github/go-kvp"
	twirpauth "github.com/github/go-twirp/client/auth"
	twirprequestid "github.com/github/go-twirp/client/requestid"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/reqobs"
	"github.com/github/launch/observability/statter"
	v1 "github.com/github/launch/proto/monolith/core/v1"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/graphqlid"
)

const (
	ActionsProductName          = "actions"
	ActionsStorageSKU           = "storage"
	SelfHostedUnknownProductSKU = "self_hosted_unknown"
)

var (
	// Mappings between monolith Twirp repository visibility to billing platform repository visibility
	monolithTwirpBillingPlatformVisibilityMapping = map[v1.RepositoryVisibility]billingplatformbase.RepositoryVisibility{
		v1.RepositoryVisibility_REPOSITORY_VISIBILITY_INVALID:  billingplatformbase.RepositoryVisibility_VISIBILITY_UNKNOWN,
		v1.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC:   billingplatformbase.RepositoryVisibility_PUBLIC,
		v1.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE:  billingplatformbase.RepositoryVisibility_PRIVATE,
		v1.RepositoryVisibility_REPOSITORY_VISIBILITY_INTERNAL: billingplatformbase.RepositoryVisibility_INTERNAL,
	}
)

type Client interface {
	CanProceedWithUsage(ctx context.Context, sku string, customerID *int64, ownerID, repoID, actorID types.GlobalID, tags statter.Tags) (*CanProceedWithUsageResp, error)
}

type CanProceedWithUsageResp struct {
	IsActionsStorageAllowed bool
	IsActionsUsageAllowed   bool
	IsOwnerSpammy           bool
	Status                  billingplatform.CanProceedWithUsageStatus
}

type client struct {
	customerAPI   billingplatform.CustomerApi
	statter       statter.Statter
	ghTwirpClient ghtwirp.Client
}

type httpClient interface {
	Do(req *http.Request) (*http.Response, error)
}

func NewHMACClientFromHTTPClient(httpClient httpClient, address string, secret string, statter statter.Statter, ghTwirpClient ghtwirp.Client) (Client, error) {
	hmacHTTPClient, err := twirpauth.NewRequestHMACSigner(secret, twirprequestid.NewForwarder(httpClient))
	if err != nil {
		return nil, fmt.Errorf("failed to create HMAC HTTP client: %w", err)
	}

	twirpTelemetry := reqobs.NewTwirpMetricsHooks(statter)
	twirpOpts := reqobs.AdaptTwirpHooksToClientOptions(twirpTelemetry, time.Now)

	bpTwirpClient := billingplatform.NewCustomerApiProtobufClient(address, hmacHTTPClient, twirpOpts...)

	return NewClient(bpTwirpClient, ghTwirpClient, statter), nil
}

func NewClient(customerAPI billingplatform.CustomerApi, ghTwirpClient ghtwirp.Client, statter statter.Statter) Client {
	return &client{
		customerAPI:   customerAPI,
		statter:       statter,
		ghTwirpClient: ghTwirpClient,
	}
}

func (c *client) CanProceedWithUsage(ctx context.Context, sku string, customerID *int64, repoOwnerID, repoID, actorID types.GlobalID, tags statter.Tags) (*CanProceedWithUsageResp, error) {
	var errs error
	// default values
	canProceedWithUsageResp := &CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}
	isOwnerSpammy, err := c.ghTwirpClient.IsUserSpammy(ctx, repoOwnerID)
	if err != nil {
		errs = errors.Join(err)
	}

	canProceedWithUsageResp.IsOwnerSpammy = isOwnerSpammy

	repoOwnerDBID, err := globalIDToInt64(repoOwnerID, types.GlobalIDUserType, types.GlobalIDOrganizationType, types.GlobalIDEnterpriseType, types.GlobalIDBusinessType)
	if err != nil {
		return canProceedWithUsageResp, errors.Join(errs, fmt.Errorf("failed to convert repoOwnerID to int64: %w", err))
	}

	repoDBID, err := globalIDToInt64(repoID, types.GlobalIDRepositoryType)
	if err != nil {
		return canProceedWithUsageResp, errors.Join(errs, fmt.Errorf("failed to convert repoID to int64: %w", err))
	}

	actorDBID, err := globalIDToInt64(actorID, types.GlobalIDUserType, types.GlobalIDBotType, types.GlobalIDMannequinType, types.GlobalIDOrganizationType) // checking for all user-based types
	if err != nil {
		return canProceedWithUsageResp, errors.Join(errs, fmt.Errorf("failed to convert actorID to int64: %w", err))
	}

	entityDetail := &billingplatformbase.EntityDetail{
		RepoId:  repoDBID,
		OwnerId: repoOwnerDBID,
		ActorId: actorDBID,
	}

	isActionsStorageAllowed, status, err := c.canProceedWithUsageForSKUAndEntityDetail(ctx, ActionsStorageSKU, customerID, entityDetail, tags)
	if err != nil {
		errs = errors.Join(errs, err)
	}

	canProceedWithUsageResp.IsActionsStorageAllowed = isActionsStorageAllowed
	canProceedWithUsageResp.Status = status
	isActionsUsageAllowed, _, err := c.canProceedWithUsageForSKUAndEntityDetail(ctx, sku, customerID, entityDetail, tags)
	if err != nil {
		errs = errors.Join(errs, err)
	}

	canProceedWithUsageResp.IsActionsUsageAllowed = isActionsUsageAllowed

	return canProceedWithUsageResp, errs
}

func (c *client) canProceedWithUsageForSKUAndEntityDetail(ctx context.Context, sku string, customerID *int64, entityDetail *billingplatformbase.EntityDetail, tags statter.Tags) (bool, billingplatform.CanProceedWithUsageStatus, error) {
	formattedSKU := fmt.Sprintf("%s_%s", ActionsProductName, sku)

	if customerID == nil { // if there is no customer ID, the customer does not have a billing relationship with us
		if strings.HasSuffix(formattedSKU, SelfHostedUnknownProductSKU) { // usage is allowed for self-hosted runners
			return true, billingplatform.CanProceedWithUsageStatus_UsageAllowed, nil
		}
		return false, billingplatform.CanProceedWithUsageStatus_NotBillable, nil
	}

	entityDetail.CustomerId = fmt.Sprintf("%d", *customerID)
	usageKey := &billingplatform.UsageKey{
		Product:      ActionsProductName,
		Sku:          formattedSKU,
		EntityDetail: entityDetail,
	}

	repositoryVisibility, err := c.ghTwirpClient.GetRepositoryVisibility(ctx, entityDetail.RepoId)
	if err != nil {
		c.statter.Counter(ctx, "billingplatform.get_repository_visibility", statter.Tags{}.Merge(tags), 1)
		return true, billingplatform.CanProceedWithUsageStatus_UsageAllowed, fmt.Errorf("failed to get repository visibility: %w", err) // default to true on failure to get visibility
	}

	visibility, ok := monolithTwirpBillingPlatformVisibilityMapping[repositoryVisibility]
	if !ok {
		usageKey.RepositoryVisibility = billingplatformbase.RepositoryVisibility_VISIBILITY_UNKNOWN
	} else {
		usageKey.RepositoryVisibility = visibility
	}

	resp, err := c.customerAPI.CanProceedWithUsage(ctx, &billingplatform.CanProceedWithUsageRequest{UsageKey: usageKey})
	if err != nil {
		c.statter.Counter(ctx, "billingplatform.can_proceed_with_usage", statter.Tags{"success": "false"}.Merge(tags), 1)
		return true, billingplatform.CanProceedWithUsageStatus_UsageAllowed, fmt.Errorf("failed to request proceed with usage: %w", err) // default to true on failure
	}

	c.statter.Counter(ctx, "billingplatform.can_proceed_with_usage", statter.Tags{"success": "true", "can_proceed": fmt.Sprint(resp.CanProceed), "sku": fmt.Sprint(formattedSKU)}.Merge(tags), 1)

	return resp.CanProceed, resp.Status, nil
}

func globalIDToInt64(globalID types.GlobalID, allowedTypes ...string) (int64, error) {
	if globalID.IsZeroValue() {
		return 0, nil
	}

	idType, id, err := graphqlid.DecodeTypeIntID(globalID.String())
	if err != nil {
		return 0, fmt.Errorf("failed to decode globalID: %w", err)
	}

	for _, allowedType := range allowedTypes {
		if idType == allowedType {
			return id, nil
		}
	}

	return 0, fmt.Errorf("globalID type %s not allowed", idType)
}

type nopClient struct {
	logger logger.Logger
}

func NewNopClient(logger logger.Logger) Client {
	return &nopClient{
		logger: logger,
	}
}

func (nc *nopClient) CanProceedWithUsage(ctx context.Context, sku string, customerID *int64, ownerID, repoID, actorID types.GlobalID, _ statter.Tags) (*CanProceedWithUsageResp, error) {
	kvps := []kvp.Field{kvp.String("gh.billing.product_sku", sku), kvp.String("gh.billing.owner.global_id", string(ownerID)), kvp.String("gh.repo.global_id", string(repoID)), kvp.String("gh.actor.id", string(actorID))}
	if customerID != nil {
		kvps = append(kvps, kvp.Int64("gh.billing.customer.id", *customerID))
	}
	nc.logger.Log(ctx, "billing platform nop client called", kvps...)

	if customerID == nil { // if there is no customer ID, the customer does not have a billing relationship with us
		if strings.HasSuffix(sku, SelfHostedUnknownProductSKU) { // usage is allowed for self-hosted runners
			return &CanProceedWithUsageResp{
				IsActionsUsageAllowed:   true,
				IsActionsStorageAllowed: false,
				IsOwnerSpammy:           false,
			}, nil
		}
		return &CanProceedWithUsageResp{
			IsActionsStorageAllowed: false,
			IsActionsUsageAllowed:   false,
			IsOwnerSpammy:           false,
		}, nil
	}

	return &CanProceedWithUsageResp{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           false,
	}, nil
}
