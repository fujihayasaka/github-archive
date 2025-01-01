package billing

import (
	"context"
	"encoding/json"
	"io"
	"net/http"

	"github.com/github/go-kvp"

	"github.com/github/launch/pkg/mu"

	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/clients/billingplatform"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"

	"github.com/github/launch/utils/appcontext"

	billingplatformProto "github.com/github/actions-proto/gen/go/billing-platform/api/v1"
)

type Service struct {
	obs                   *observability.Observability
	db                    deployer.AzpResourcesLoader
	verifier              *hmac.HTTPVerifier
	ghTwirpClient         ghtwirp.Client
	billingPlatformClient billingplatform.Client
}

func NewService(
	obs *observability.Observability,
	db deployer.AzpResourcesLoader,
	verifier *hmac.HTTPVerifier,
	ghTwirpClient ghtwirp.Client,
	billingPlatformClient billingplatform.Client,
) *Service {
	return &Service{
		obs:                   obs,
		db:                    db,
		verifier:              verifier,
		ghTwirpClient:         ghTwirpClient,
		billingPlatformClient: billingPlatformClient,
	}
}

const billingLimitsRoute = "/actions/billing/limits"

// This endpoint is used by the Larger Runners service, because it needs to make an independent
// call outside of the pre-job request. For context, see the ADR here:
// https://github.com/github/c2c-actions/blob/main/docs/adrs/5788-pre-job-check.md#launch-changes
func (s *Service) HandleGetBillingDetails(resp http.ResponseWriter, request *http.Request) {
	ctx, span := tracing.Start(request.Context())
	defer span.End()

	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	body, err := io.ReadAll(request.Body)
	if err != nil {
		s.respondWithError(ctx, http.StatusBadRequest, err, resp)
		return
	}

	if err := s.verifier.Verify(ctx, request, body); err != nil {
		s.respondWithError(ctx, http.StatusForbidden, err, resp)
		return
	}

	tenantID := request.URL.Query().Get("tenantId")

	if tenantID == "" {
		resp.WriteHeader(http.StatusNotFound)
		return
	}

	res, found, err := s.db.GetByTenantID(ctx, tenantID)
	if err != nil {
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
		return
	}

	if !found {
		resp.WriteHeader(http.StatusNotFound)
		return
	}

	entityID := res.EntityID
	actorID := entityID

	productSku := request.URL.Query().Get("productSku")

	entityType, entityDatabaseID, err := entityID.Decode()
	if err != nil {
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
		return
	}

	// It's possible the entity is not "Organization" or "Enterprise".
	// We only need to make a Twirp call for the Organization case to see
	// if there's an associated enterprise to check the billing platform FF on.
	// If there is, we check the FF against that. Otherwise, we check the FF
	// against whatever the original provided entity ID was.
	if entityType == ghtwirp.OrganizationType {
		owner, err := s.ghTwirpClient.GetOrganizationOwner(ctx, entityDatabaseID)
		if err != nil {
			if terrors.IsNotFoundError(err) {
				s.respondWithError(ctx, http.StatusNotFound, err, resp)
				return
			}
			s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
			return
		}

		if owner.Business != nil {
			actorID = owner.Business.GlobalID
		}
	}

	response := &ghtwirp.WorkflowBillingDetails{}
	if s.ghTwirpClient.IsFeatureEnabledForActor(ctx, github.BillingCanProceedWithUsageProductEnabled, actorID) {
		s.obs.Debug(ctx, "using billing platform for receiver billing checks", kvp.String("gh.launch.entity.global_id", entityID.String()))
		accountDetails, err := s.ghTwirpClient.GetAccountDetails(ctx, entityID)
		if err != nil {
			s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
			return
		}

		nilGlobalID := types.NilGlobalID
		canProceedWithUsageResp, err := s.billingPlatformClient.CanProceedWithUsage(
			ctx,
			productSku,
			&accountDetails.CustomerID,
			entityID,
			nilGlobalID,
			nilGlobalID,
			statter.Tags{"caller": "larger_runners"}, // see the comment at the top of this method for an explanation
		)
		if err != nil {
			if terrors.IsNotFoundError(err) {
				s.obs.Statter.Counter(
					ctx,
					"receiver.handlegetbillingdetails.customer_not_found",
					statter.Tags{},
					1,
				)
				err := s.handleMeuseRequest(ctx, response, entityID, productSku)
				if err != nil {
					s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
					return
				}

				if err := json.NewEncoder(resp).Encode(response); err != nil {
					s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
					return
				}

				return
			}

			s.obs.Statter.Counter(
				ctx,
				"receiver.handlegetbillingdetails.billing_platform_usage_checks",
				statter.Tags{"success": "false"},
				1,
			)
			s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
			return
		}

		s.obs.Statter.Counter(
			ctx,
			"receiver.handlegetbillingdetails.billing_platform_usage_checks",
			statter.Tags{"success": "true"},
			1,
		)

		s.obs.Debug(
			ctx,
			"Billing platform usage checks",
			kvp.String("gh.billing.product_sku", productSku),
			kvp.Bool("gh.billing.actions_storage_allowed", canProceedWithUsageResp.IsActionsStorageAllowed),
			kvp.Bool("gh.billing.actions_usage_allowed", canProceedWithUsageResp.IsActionsUsageAllowed),
			kvp.Bool("gh.launch.owner.spammy", canProceedWithUsageResp.IsOwnerSpammy),
			kvp.String("gh.launch.entity.global_id", entityID.String()),
			kvp.String("gh.actions.tenant.id", tenantID),
			kvp.Int64("gh.billing.customer.id", accountDetails.CustomerID),
		)

		if canProceedWithUsageResp.Status == billingplatformProto.CanProceedWithUsageStatus_ProductNotEnabled {
			s.obs.Statter.Counter(
				ctx,
				"receiver.handlegetbillingdetails.product_not_enabled",
				statter.Tags{},
				1,
			)

			err := s.handleMeuseRequest(ctx, response, entityID, productSku)
			if err != nil {
				s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
				return
			}

			if err := json.NewEncoder(resp).Encode(response); err != nil {
				s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
				return
			}

			return
		}

		response.IsActionsStorageAllowed = canProceedWithUsageResp.IsActionsStorageAllowed
		response.IsActionsUsageAllowed = canProceedWithUsageResp.IsActionsUsageAllowed
		response.IsOwnerSpammy = canProceedWithUsageResp.IsOwnerSpammy
	} else if s.ghTwirpClient.IsFeatureEnabledForActor(ctx, github.ActionsUseBillingPlatform, actorID) {
		s.obs.Debug(ctx, "using billing platform for receiver billing checks", kvp.String("gh.launch.entity.global_id", entityID.String()))
		accountDetails, err := s.ghTwirpClient.GetAccountDetails(ctx, entityID)
		if err != nil {
			s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
			return
		}

		nilGlobalID := types.NilGlobalID
		canProceedWithUsageResp, err := s.billingPlatformClient.CanProceedWithUsage(
			ctx,
			productSku,
			&accountDetails.CustomerID,
			entityID,
			nilGlobalID,
			nilGlobalID,
			statter.Tags{"caller": "larger_runners"}, // see the comment at the top of this method for an explanation
		)
		if err != nil {
			s.obs.Statter.Counter(
				ctx,
				"receiver.handlegetbillingdetails.billing_platform_usage_checks",
				statter.Tags{"success": "false"},
				1,
			)
			s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
			return
		}
		s.obs.Statter.Counter(
			ctx,
			"receiver.handlegetbillingdetails.billing_platform_usage_checks",
			statter.Tags{"success": "true"},
			1,
		)

		s.obs.Debug(
			ctx,
			"Billing platform usage checks",
			kvp.String("gh.billing.product_sku", productSku),
			kvp.Bool("gh.billing.actions_storage_allowed", canProceedWithUsageResp.IsActionsStorageAllowed),
			kvp.Bool("gh.billing.actions_usage_allowed", canProceedWithUsageResp.IsActionsUsageAllowed),
			kvp.Bool("gh.launch.owner.spammy", canProceedWithUsageResp.IsOwnerSpammy),
			kvp.String("gh.launch.entity.global_id", entityID.String()),
			kvp.String("gh.actions.tenant.id", tenantID),
			kvp.Int64("gh.billing.customer.id", accountDetails.CustomerID),
		)

		response.IsActionsStorageAllowed = canProceedWithUsageResp.IsActionsStorageAllowed
		response.IsActionsUsageAllowed = canProceedWithUsageResp.IsActionsUsageAllowed
		response.IsOwnerSpammy = canProceedWithUsageResp.IsOwnerSpammy

	} else {
		err := s.handleMeuseRequest(ctx, response, entityID, productSku)
		if err != nil {
			s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
			return
		}
	}

	if err := json.NewEncoder(resp).Encode(response); err != nil {
		s.respondWithError(ctx, http.StatusInternalServerError, err, resp)
		return
	}

	resp.WriteHeader(http.StatusOK)
}

func (s *Service) handleMeuseRequest(ctx context.Context, response *ghtwirp.WorkflowBillingDetails, entityID types.GlobalID, productSku string) error {
	billingResponse, err := s.ghTwirpClient.GetBillingDetailsForEntity(ctx, entityID, productSku)
	if err != nil {
		return err
	}

	response.IsActionsStorageAllowed = billingResponse.IsActionsStorageAllowed
	response.IsActionsUsageAllowed = billingResponse.IsActionsUsageAllowed
	response.IsOwnerSpammy = billingResponse.IsOwnerSpammy

	return nil
}

func (s *Service) Routes() []mu.Route {
	return []mu.Route{
		mu.Get(billingLimitsRoute, s.HandleGetBillingDetails),
	}
}

func (s *Service) ServiceContext(req *http.Request) {
	appcontext.SetupServiceContext(req)
}

func (s *Service) respondWithError(ctx context.Context, code int, err error, resp http.ResponseWriter) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	s.obs.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))

	span.RecordError(err)
	http.Error(resp, http.StatusText(code), code)
}
