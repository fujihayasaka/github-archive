package remediation

import (
	"context"
	"fmt"
	"time"

	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/policy"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

type policyGetter interface {
	// FetchPolicy reloads the policy and caches it
	FetchPolicy(ctx context.Context) error
}

type organizationPolicyFetcher struct {
	app            *application.Application
	organizationID uint64
	policy         *proto.OrganizationPolicy
}

func (opf *organizationPolicyFetcher) FetchPolicy(ctx context.Context) error {
	orgPolicy, err := opf.app.Subsystems.Storage.GetOrganizationPolicyByOrgID(ctx, opf.organizationID)
	if err != nil {
		return fmt.Errorf("failed to fetch organization policy: %w", err)
	}
	opf.policy = orgPolicy
	return nil
}

// GetPolicy returns the cached organization policy. FetchPolicy must be called first to populate the cache.
func (opf *organizationPolicyFetcher) GetPolicy() *proto.OrganizationPolicy {
	return opf.policy
}

// AddLicensesToOrganizationPolicy adds the given SPDX IDs to the organization policy and returns the updated policy.
// It also triggers asynchronous closure of affected alerts.
func AddLicensesToOrganizationPolicy(
	ctx context.Context,
	app *application.Application,
	spdxIDs []string,
	distributionContext string,
	organizationID uint64,
) (*proto.OrganizationPolicy, error) {
	policyFetcher := &organizationPolicyFetcher{
		app:            app,
		organizationID: organizationID,
	}

	err := addLicensesToPolicyLevel(ctx, app, spdxIDs, distributionContext, 0, organizationID, 0, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, policyFetcher)
	if err != nil {
		return nil, fmt.Errorf("failed to add licenses to organization policy: %w", err)
	}

	return policyFetcher.GetPolicy(), nil
}

type enterprisePolicyFetcher struct {
	app          *application.Application
	enterpriseID uint64
	policy       *proto.EnterprisePolicy
}

func (epf *enterprisePolicyFetcher) FetchPolicy(ctx context.Context) error {
	enterprisePolicy, err := epf.app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, epf.enterpriseID)
	if err != nil {
		return fmt.Errorf("failed to fetch enterprise policy: %w", err)
	}
	epf.policy = enterprisePolicy
	return nil
}

// GetPolicy returns the cached enterprise policy. FetchPolicy must be called first to populate the cache.
func (epf *enterprisePolicyFetcher) GetPolicy() *proto.EnterprisePolicy {
	return epf.policy
}

// AddLicensesToEnterprisePolicy adds the given SPDX IDs to the enterprise policy and returns the updated policy.
// It also triggers asynchronous closure of affected alerts.
func AddLicensesToEnterprisePolicy(
	ctx context.Context,
	app *application.Application,
	spdxIDs []string,
	distributionContext string,
	enterpriseID uint64,
) (*proto.EnterprisePolicy, error) {
	policyFetcher := &enterprisePolicyFetcher{
		app:          app,
		enterpriseID: enterpriseID,
	}

	err := addLicensesToPolicyLevel(ctx, app, spdxIDs, distributionContext, enterpriseID, 0, 0, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, policyFetcher)
	if err != nil {
		return nil, fmt.Errorf("failed to add licenses to enterprise policy: %w", err)
	}

	return policyFetcher.GetPolicy(), nil
}

func addLicensesToPolicyLevel(
	ctx context.Context,
	app *application.Application,
	spdxIDs []string,
	distributionContext string,
	enterpriseID, organizationID, repositoryID uint64,
	level proto.PolicyLevel,
	fetcher policyGetter,
) error {
	// Normalize all SPDX IDs to canonical case
	normalizedSpdxIDs := make([]string, len(spdxIDs))
	for i, spdxID := range spdxIDs {
		normalizedSpdxIDs[i] = evaluator.NormalizeSpdxID(spdxID)
	}

	var policyID uint64
	switch level {
	case proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE:
		policyID = enterpriseID
	case proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION:
		policyID = organizationID
	default:
		return fmt.Errorf("invalid policy level: %v", level)
	}
	policyWriter, err := policy.NewWriter(app, level, policyID)
	if err != nil {
		return fmt.Errorf("failed to create policy writer: %w", err)
	}

	err = policyWriter.AddLicenses(ctx, normalizedSpdxIDs, []string{distributionContext})
	if err != nil {
		return fmt.Errorf("failed to add licenses to policy: %w", err)
	}

	// Fetch the updated policy to return
	err = fetcher.FetchPolicy(ctx)
	if err != nil {
		return fmt.Errorf("failed to fetch updated policy: %w", err)
	}

	// Create event body for side-effect alerts
	eventBodyPayload := models.LicensesAddedEventBody{
		Licenses: spdxIDs,
		Level:    models.PolicyLevelToString(level),
	}

	// Spawn async goroutine to close affected alerts
	// WithoutCancel detaches from request cancellation while preserving context tags
	asyncCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 1*time.Minute)
	go func() {
		defer cancel()

		err := CheckAndCloseAffectedAlertsForLicenses(
			asyncCtx,
			app,
			eventBodyPayload,
			level,
			enterpriseID,
			organizationID,
			repositoryID,
			nil, // No user - this is a system/bot-initiated closure
			nil, // No original alert for direct policy updates
		)
		if err != nil {
			app.Logger.Named("policy-update").WithError(err).Error("failed to close affected alerts asynchronously")
		}
	}()

	return nil
}
