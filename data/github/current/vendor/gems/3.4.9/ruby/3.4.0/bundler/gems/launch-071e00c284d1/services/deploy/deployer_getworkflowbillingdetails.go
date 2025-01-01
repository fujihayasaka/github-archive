package deploy

import (
	"context"

	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/utils/ghtenant"

	"github.com/pkg/errors"
	errs "github.com/pkg/errors"
	"github.com/twitchtv/twirp"

	"github.com/github/go-kvp"
	gokvp "github.com/github/go-kvp"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"

	billingplatform "github.com/github/actions-proto/gen/go/billing-platform/api/v1"
)

const (
	ExperimentalProductSKU      = "experimental"
	SelfHostedUnknownProductSKU = "self_hosted_unknown"
)

//gocyclo:ignore
func (s *service) GetWorkflowBillingDetails(ctx context.Context, req *pb.GetWorkflowBillingDetailsRequest) (*pb.WorkflowBillingDetailsResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	workflowID := req.GetWorkflowID()
	jobID := req.GetJobID()
	isHostedRunner := req.GetIsHostedRunner()
	productSku := req.GetProductSku()

	ctx = ctxstash.WithFields(ctx,
		gokvp.String("gh.launch.workflow.identifier", workflowID),
		gokvp.String("gh.launch.job.id", jobID),
		gokvp.Bool("gh.launch.hosted_runner", isHostedRunner),
		gokvp.String("gh.billing.product_sku", productSku),
	)

	if workflowID == "" {
		err := twirp.RequiredArgumentError("workflowID")
		s.cfg.Log.Report(ctx, errors.Wrap(err, "GetWorkflowID"), kvp.String("code.function", "GetWorkflowID"))
		return nil, err
	}

	dataForTokenReq, ok, err := s.cfg.WorkflowBuilds.GetDataForTokenRequest(ctx, workflowID)
	if err != nil {
		s.cfg.Log.Report(ctx, errors.Wrap(err, "GetDataForTokenRequest"), kvp.String("code.function", "GetDataForTokenRequest"))
		return nil, twirp.InternalError("Internal error")
	}
	if !ok {
		return nil, twirp.NotFoundError("no workflow with this ID")
	}

	// GitHubTenantID will be a nil pointer for non-multi-tenant modes.
	if s.IsMultiTenant {
		if dataForTokenReq.GitHubTenantID == nil {
			return nil, tracing.RecordError(span, errs.New("GitHub tenant id in workflow build state must not be nil"))
		}

		ctx, err = ghtenant.ContextWithTenantID(ctx, *dataForTokenReq.GitHubTenantID, s.IsMultiTenant)
		if err != nil {
			return nil, tracing.RecordError(span, errs.Wrap(err, "expected valid GitHub tenant id to be set in workflow build state"))
		}
	}

	appName, _, isDynamic := flowevents.ExtractDynamicWorkflowFilePath(dataForTokenReq.WorkflowFilePath)
	if isDynamic && (appName == "pages" || appName == "dependabot") {
		isSpammy, err := s.cfg.GithubTwirpClient.IsUserFromDatabaseIDSpammy(ctx, int64(dataForTokenReq.WorkflowMetadata.RepositoryOwner.ID))
		if err != nil {
			return nil, tracing.RecordError(span, errs.Wrap(err, "Error trying to check if owner is spammy"))
		}

		s.cfg.Stats.Counter(ctx, "billing-skip-dynamic-workflow", statter.Tags{"app": appName}, 1)

		return &pb.WorkflowBillingDetailsResponse{
			IsStorageAllowed: true,
			IsUsageAllowed:   true,
			IsOwnerSpammy:    isSpammy,
			RepositoryId:     types.IdentityFromGlobalID((dataForTokenReq.RepositoryID)),
			IsBillingChecked: true,
		}, nil
	}

	//	Handle case of experimental billing by product sku and actor
	if productSku == ExperimentalProductSKU {
		isExperimentalBillingEnabled := s.cfg.GithubTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, github.ExperimentalBillingFeatureFlag, dataForTokenReq.RepositoryID)
		if isExperimentalBillingEnabled {
			isSpammy, err := s.cfg.GithubTwirpClient.IsUserFromDatabaseIDSpammy(ctx, int64(dataForTokenReq.WorkflowMetadata.RepositoryOwner.ID))
			if err != nil {
				return nil, tracing.RecordError(span, errs.Wrap(err, "Error trying to check if owner is spammy"))
			}

			s.cfg.Stats.Counter(ctx, "billing-skip-experimental", nil, 1)

			return &pb.WorkflowBillingDetailsResponse{
				IsStorageAllowed: true,
				IsUsageAllowed:   true,
				IsOwnerSpammy:    isSpammy,
				RepositoryId:     types.IdentityFromGlobalID((dataForTokenReq.RepositoryID)),
				IsBillingChecked: true,
			}, nil
		}
	}

	/*
		New code path switch to GetBillingDetailsByEntity
	*/

	if s.cfg.GithubTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, github.BillingCanProceedWithUsageProductEnabled, dataForTokenReq.RepositoryID) {
		isBillingVNextChecked := true

		// If the product sku is empty and this is not a hosted runner,
		// we can be confident it is a self-hosted runner.
		// eventually, we'll want to remove this in favor of actions service
		// always sending a product sku:
		// https://github.com/github/c2c-actions-checks/issues/1727
		if productSku == "" && !isHostedRunner {
			productSku = SelfHostedUnknownProductSKU
		}

		canProceedWithUsageResp, err := s.cfg.BillingPlatformTwirpClient.CanProceedWithUsage(
			ctx,
			productSku,
			dataForTokenReq.WorkflowMetadata.CustomerID,
			types.NewGlobalID(ctx, dataForTokenReq.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
			dataForTokenReq.RepositoryID,
			types.NewGlobalID(ctx, dataForTokenReq.WorkflowMetadata.InvokingUser.GlobalRelayID),
			statter.Tags{"caller": "workflow_billing_details"},
		)

		if err != nil {
			// user has no customer record in billing platform, we should call Meuse instead
			if terrors.IsNotFoundError(err) {
				s.cfg.Stats.Counter(
					ctx,
					"deploy.getworkflowbillingdetails.customer_not_found",
					statter.Tags{},
					1,
				)
				return s.handleMeuseWorkflowBillingDetails(ctx, req, dataForTokenReq, span)
			} else {
				s.cfg.Stats.Counter(
					ctx,
					"deploy.getworkflowbillingdetails.billing_platform_usage_checks",
					statter.Tags{"success": "false", "fallback": "true"},
					1,
				)
				kvps := []kvp.Field{
					kvp.String("code.function", "CanProceedWithUsage"),
					kvp.String("gh.billing.product_sku", productSku),
					kvp.String("gh.repo.global_id", dataForTokenReq.RepositoryID.String()),
					kvp.Bool("gh.launch.fallback", true),
				}

				if dataForTokenReq.WorkflowMetadata.CustomerID != nil {
					kvps = append(kvps, kvp.Int64("gh.billing.customer.id", *dataForTokenReq.WorkflowMetadata.CustomerID))
				}
				s.cfg.Log.Report(
					ctx,
					errors.Wrap(
						err,
						"failed to check can proceed with storage usage",
					),
					kvps...,
				)
				isBillingVNextChecked = false
				err := s.cfg.JobsRepo.UpdateBillingChecked(ctx, workflowID, jobID, false)
				if err != nil {
					return nil, tracing.RecordError(span, errs.Wrap(err, "Error updating billing_checked column"))
				}
			}
		} else {
			// usage for this product is not enabled, we should call Meuse instead
			if canProceedWithUsageResp.Status == billingplatform.CanProceedWithUsageStatus_ProductNotEnabled {
				s.cfg.Stats.Counter(
					ctx,
					"deploy.getworkflowbillingdetails.product_not_enabled",
					statter.Tags{},
					1,
				)

				return s.handleMeuseWorkflowBillingDetails(ctx, req, dataForTokenReq, span)
			} else {
				s.cfg.Stats.Counter(
					ctx,
					"deploy.getworkflowbillingdetails.billing_platform_usage_checks",
					statter.Tags{
						"success": "true",
					},
					1,
				)

				kvps := []kvp.Field{
					kvp.String("gh.billing.product_sku", productSku),
					kvp.Bool("gh.launch.storage_allowed", canProceedWithUsageResp.IsActionsStorageAllowed),
					kvp.Bool("gh.launch.actions_usage_allowed", canProceedWithUsageResp.IsActionsUsageAllowed),
					kvp.Bool("gh.launch.owner.spammy", canProceedWithUsageResp.IsOwnerSpammy),
					kvp.String("gh.repo.global_id", dataForTokenReq.RepositoryID.String()),
				}

				if dataForTokenReq.WorkflowMetadata.CustomerID != nil {
					kvps = append(kvps, kvp.Int64("gh.billing.customer.id", *dataForTokenReq.WorkflowMetadata.CustomerID))
				}
				s.cfg.Log.Debug(
					ctx,
					"Billing platform usage checks",
					kvps...,
				)
			}
		}

		return &pb.WorkflowBillingDetailsResponse{
			IsStorageAllowed: canProceedWithUsageResp.IsActionsStorageAllowed,
			IsUsageAllowed:   canProceedWithUsageResp.IsActionsUsageAllowed,
			IsOwnerSpammy:    canProceedWithUsageResp.IsOwnerSpammy,
			RepositoryId:     types.IdentityFromGlobalID(dataForTokenReq.RepositoryID),
			IsBillingChecked: isBillingVNextChecked,
		}, nil

	} else if s.cfg.GithubTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, github.ActionsUseBillingPlatform, dataForTokenReq.RepositoryID) {
		// Any customer on billing vnext should check usage against the billing platform

		// If the product sku is empty and this is not a hosted runner,
		// we can be confident it is a self-hosted runner.
		// eventually, we'll want to remove this in favor of actions service
		// always sending a product sku:
		// https://github.com/github/c2c-actions-checks/issues/1727
		if productSku == "" && !isHostedRunner {
			productSku = SelfHostedUnknownProductSKU
		}

		if !s.validBillingPlatformParameters(ctx, productSku, dataForTokenReq) {
			return nil, tracing.RecordError(span, errors.New("invalid billing platform parameters"))
		}

		isBillingVNextChecked := true
		canProceedWithUsageResp, err := s.cfg.BillingPlatformTwirpClient.CanProceedWithUsage(
			ctx,
			productSku,
			dataForTokenReq.WorkflowMetadata.CustomerID,
			types.NewGlobalID(ctx, dataForTokenReq.WorkflowMetadata.RepositoryOwner.GlobalRelayID),
			dataForTokenReq.RepositoryID,
			types.NewGlobalID(ctx, dataForTokenReq.WorkflowMetadata.InvokingUser.GlobalRelayID),
			statter.Tags{"caller": "workflow_billing_details"},
		)
		if err != nil {
			s.cfg.Stats.Counter(
				ctx,
				"deploy.getworkflowbillingdetails.billing_platform_usage_checks",
				statter.Tags{"success": "false", "fallback": "true"},
				1,
			)
			kvps := []kvp.Field{
				kvp.String("code.function", "CanProceedWithUsage"),
				kvp.String("gh.billing.product_sku", productSku),
				kvp.String("gh.repo.global_id", dataForTokenReq.RepositoryID.String()),
				kvp.Bool("gh.launch.fallback", true),
			}

			if dataForTokenReq.WorkflowMetadata.CustomerID != nil {
				kvps = append(kvps, kvp.Int64("gh.billing.customer.id", *dataForTokenReq.WorkflowMetadata.CustomerID))
			}
			s.cfg.Log.Report(
				ctx,
				errors.Wrap(
					err,
					"failed to check can proceed with storage usage",
				),
				kvps...,
			)
			isBillingVNextChecked = false
			err := s.cfg.JobsRepo.UpdateBillingChecked(ctx, workflowID, jobID, false)
			if err != nil {
				return nil, tracing.RecordError(span, errs.Wrap(err, "Error updating billing_checked column"))
			}
		} else {
			s.cfg.Stats.Counter(
				ctx,
				"deploy.getworkflowbillingdetails.billing_platform_usage_checks",
				statter.Tags{
					"success": "true",
				},
				1,
			)

			kvps := []kvp.Field{
				kvp.String("gh.billing.product_sku", productSku),
				kvp.Bool("gh.launch.storage_allowed", canProceedWithUsageResp.IsActionsStorageAllowed),
				kvp.Bool("gh.launch.actions_usage_allowed", canProceedWithUsageResp.IsActionsUsageAllowed),
				kvp.Bool("gh.launch.owner.spammy", canProceedWithUsageResp.IsOwnerSpammy),
				kvp.String("gh.repo.global_id", dataForTokenReq.RepositoryID.String()),
			}

			if dataForTokenReq.WorkflowMetadata.CustomerID != nil {
				kvps = append(kvps, kvp.Int64("gh.billing.customer.id", *dataForTokenReq.WorkflowMetadata.CustomerID))
			}
			s.cfg.Log.Debug(
				ctx,
				"Billing platform usage checks",
				kvps...,
			)
		}

		return &pb.WorkflowBillingDetailsResponse{
			IsStorageAllowed: canProceedWithUsageResp.IsActionsStorageAllowed,
			IsUsageAllowed:   canProceedWithUsageResp.IsActionsUsageAllowed,
			IsOwnerSpammy:    canProceedWithUsageResp.IsOwnerSpammy,
			RepositoryId:     types.IdentityFromGlobalID(dataForTokenReq.RepositoryID),
			IsBillingChecked: isBillingVNextChecked,
		}, nil
	}

	return s.handleMeuseWorkflowBillingDetails(ctx, req, dataForTokenReq, span)
}

func (s *service) handleMeuseWorkflowBillingDetails(ctx context.Context, req *pb.GetWorkflowBillingDetailsRequest, dataForTokenReq *deployer.DataForTokenRequest, span trace.Span) (*pb.WorkflowBillingDetailsResponse, error) {
	workflowID := req.GetWorkflowID()
	jobID := req.GetJobID()
	isHostedRunner := req.GetIsHostedRunner()
	productSku := req.GetProductSku()
	hasError := false
	var billingResponse *ghtwirp.WorkflowBillingDetails
	var err error

	if isHostedRunner || productSku != "" {
		billingResponse, err = s.cfg.GithubTwirpBillingClient.GetBillingDetailsForEntity(ctx, dataForTokenReq.RepositoryID, productSku)
		if err != nil {
			if terrors.IsNotFoundError(err) {
				return nil, twirp.NotFoundError("Billing details for repository not found")
			}

			s.cfg.Log.Report(ctx, errors.Wrap(err, "GetBillingDetailsForEntity"), kvp.String("code.function", "GetBillingDetailsForEntity"))
			s.cfg.Stats.Counter(ctx, "github.billing-check-by-entity", statter.Tags{"type": "billing_response_for_entity_err", "success": "false"}, 1)

			hasError = true
		}
		s.cfg.Stats.Counter(ctx, "github.billing-check-by-entity", statter.Tags{"type": "billing_response_for_entity", "success": "true"}, 1)

	} else {
		billingResponse, err = s.cfg.GithubTwirpBillingClient.GetBillingDetails(ctx, dataForTokenReq.RepositoryID)
		if err != nil {
			if terrors.IsNotFoundError(err) {
				return nil, twirp.NotFoundError("Billing details for repository not found")
			}

			s.cfg.Stats.Counter(ctx, "github.billing-check", statter.Tags{"type": "billing_response_err", "success": "false"}, 1)
			s.cfg.Log.Report(ctx, errors.Wrap(err, "GetBillingDetails"), kvp.String("code.function", "GetBillingDetails"))

			hasError = true
		}
	}

	if !hasError && billingResponse == nil {
		s.cfg.Stats.Counter(ctx, "github.billing-check", statter.Tags{"type": "billing_response_nil", "success": "false"}, 1)
		s.cfg.Log.Report(ctx, errors.New("GetBillingDetails: Billing Response is nil"), kvp.String("code.function", "GetBillingDetails"))

		hasError = true
	}

	// ignore all errors and always allow workflow execution, just log and stats https://github.com/github/c2c-actions-checks/issues/225
	if hasError {
		err := s.cfg.JobsRepo.UpdateBillingChecked(ctx, workflowID, jobID, false)
		if err != nil {
			return nil, tracing.RecordError(span, errs.Wrap(err, "Error updating billing_checked column"))
		}
		return &pb.WorkflowBillingDetailsResponse{
			IsStorageAllowed: true,
			IsUsageAllowed:   true,
			IsOwnerSpammy:    false,
			RepositoryId:     types.IdentityFromGlobalID((dataForTokenReq.RepositoryID)),
			IsBillingChecked: false,
		}, nil
	}

	s.cfg.Stats.Counter(ctx, "github.billing-check", statter.Tags{"success": "true"}, 1)

	return &pb.WorkflowBillingDetailsResponse{
		IsStorageAllowed: billingResponse.IsActionsStorageAllowed,
		IsUsageAllowed:   billingResponse.IsActionsUsageAllowed,
		IsOwnerSpammy:    billingResponse.IsOwnerSpammy,
		RepositoryId:     types.IdentityFromGlobalID(dataForTokenReq.RepositoryID),
		IsBillingChecked: true,
	}, nil
}

func (s *service) validBillingPlatformParameters(ctx context.Context, sku string, dataForTokenReq *deployer.DataForTokenRequest) bool {
	if sku == "" {
		s.cfg.Log.Report(ctx, errors.New("sku is empty"), kvp.String("code.function", "validateBillingPlatformParameters"))
		return false
	}

	if dataForTokenReq == nil || dataForTokenReq.WorkflowMetadata == nil {
		s.cfg.Log.Report(ctx, errors.New("workflowBuildState or workflowBuildState.WorkflowMetadata is nil"), kvp.String("code.function", "validateBillingPlatformParameters"))
		return false
	}

	validRepositoryOwner := dataForTokenReq.WorkflowMetadata.RepositoryOwner != nil &&
		dataForTokenReq.WorkflowMetadata.RepositoryOwner.GlobalRelayID != ""
	if !validRepositoryOwner {
		s.cfg.Log.Report(ctx, errors.New("invalid repository owner"), kvp.String("code.function", "validateBillingPlatformParameters"))
		return false
	}

	validInvokingUser := dataForTokenReq.WorkflowMetadata.InvokingUser != nil &&
		dataForTokenReq.WorkflowMetadata.InvokingUser.GlobalRelayID != ""
	if !validInvokingUser {
		s.cfg.Log.Report(ctx, errors.New("invalid invoking user"), kvp.String("code.function", "validateBillingPlatformParameters"))
		return false
	}

	return true
}
