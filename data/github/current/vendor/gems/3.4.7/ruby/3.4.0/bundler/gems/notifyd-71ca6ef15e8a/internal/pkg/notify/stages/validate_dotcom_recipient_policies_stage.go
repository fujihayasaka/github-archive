package stages

import (
	"context"
	"fmt"
	"strings"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/dotcom/policy"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/tenancy"
	notifyd_pb "github.com/github/notifyd/proto/notifyd/v1"
)

// FIXME: Return a NotFound error from the Twirp API in the Monolith so it's easier to
// check and skip
const repositoryNotFoundResponse = "twirp error invalid_argument: Repository not found"

type validateDotcomRecipientPoliciesStage struct {
	dotcomPolicyChecker policy.Checker
	clock               clockpkg.Clock
	telem               *telemetry.Provider
	statter             stats.Client
}

// NewValidateDotcomRecipientPoliciesStage creates a new validate dotcom recipient policies stage.
func NewValidateDotcomRecipientPoliciesStage(dotcomPolicyChecker policy.Checker, clock clockpkg.Clock, telem *telemetry.Provider, statter stats.Client) IValidateDotcomRecipientPoliciesStage {
	return &validateDotcomRecipientPoliciesStage{
		dotcomPolicyChecker: dotcomPolicyChecker,
		clock:               clock,
		telem:               telem,
		statter:             statter,
	}
}

// ValidateDotcomPolicies validates dotcom policies.
func (s *validateDotcomRecipientPoliciesStage) ValidateDotcomPolicies(ctx context.Context, tenant tenancy.Tenant, recipientIDsToReasons notify.RecipientIDToReasons, msg *notify.Notification) (notify.RecipientIDToReasons, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	// TODO: mobile-auth-requests are a special case that should be handled via a special endpoint
	if strings.HasPrefix(msg.ID, "mobile-auth-request/user-") {
		return recipientIDsToReasons, nil
	}

	start := s.clock.Now()
	defer func() {
		s.statter.DistributionMs(statsTimingKey, stats.Tags{"stage": "validate_dotcom_recipient_policies"}, s.clock.Since(start))
	}()

	total := len(recipientIDsToReasons)
	s.telem.Logger.WithContext(ctx).
		WithFields(kvp.Int("gh.notifyd.recipients_to_check_count", total)).
		Info("checking notify policy")
	// Add policy check if one is available
	if msg.ShouldRequestPolicy() {
		request := msg.PolicyRequestPB()

		if err := s.checkRecipientsNotifyPolicy(ctx, tenant, recipientIDsToReasons, request); err != nil {
			return nil, errors.Wrap(err, "error checking notify policy").With(errors.MarkRetriable())
		}
	}

	return recipientIDsToReasons, nil
}

func (s *validateDotcomRecipientPoliciesStage) checkRecipientsNotifyPolicy(ctx context.Context, tenant tenancy.Tenant, recipientIDsToReasons notify.RecipientIDToReasons, notifyContext *notifyd_pb.ShouldNotifyRequestContext) error {
	batchCheckResult, err := s.dotcomPolicyChecker.BatchCheckNotifyPolicy(ctx, tenant, recipientIDsToReasons, notifyContext)
	if err != nil {
		return err
	}

	removedRecipientsCount := 0
	for userID, checkResult := range batchCheckResult.UserIDToCheckResult {
		if !checkResult.IsDeliverable {
			delete(recipientIDsToReasons, userID)
			s.telem.Logger.WithContext(ctx).
				WithFields(
					kvp.String("gh.notifyd.reason", checkResult.NotDeliverableReason),
					kvp.Int64("gh.user.id", userID),
				).
				Info("skipping notification delivery because not passed notify policy")
			s.statter.Counter("notify", stats.Tags{"status": "skipped", "reason": strings.ReplaceAll(checkResult.NotDeliverableReason, " ", "_")}, 1)
			removedRecipientsCount++
		}
	}

	if removedRecipientsCount > 0 {
		s.telem.Logger.WithContext(ctx).Info(fmt.Sprintf("removed %d recipients from delivery batch", removedRecipientsCount))
	}

	return nil
}

// ValidateIgnoredRepository validates ignored repository.
func (s *validateDotcomRecipientPoliciesStage) ValidateIgnoredRepository(ctx context.Context, tenant tenancy.Tenant, recipientIDsToReasons notify.RecipientIDToReasons, msg *notify.Notification) (notify.RecipientIDToReasons, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	start := s.clock.Now()
	defer func() {
		s.statter.DistributionMs(statsTimingKey, stats.Tags{"stage": "validate_dotcom_recipient_policies"}, s.clock.Since(start))
	}()

	total := len(recipientIDsToReasons)
	s.telem.Logger.WithContext(ctx).
		WithFields(kvp.Int("gh.notifyd.recipients_to_check_count", total)).
		Info("checking ignored repository")

	var repositoryID int64

	// TODO: mobile-auth-requests are a special case that should be handled via a special endpoint
	if strings.HasPrefix(msg.ID, "mobile-auth-request/user-") {
		return recipientIDsToReasons, nil
	}

	// Skip checking policy if we had no repository ID defined
	if !msg.Context.HasRepository() {
		return recipientIDsToReasons, nil
	}

	repositoryID = msg.Context.RepositoryID

	results, err := s.dotcomPolicyChecker.BatchCheckIgnoredRepository(ctx, tenant, repositoryID, recipientIDsToReasons)
	if err != nil {
		if err.Error() == repositoryNotFoundResponse {
			// If the repository is not found, there is nothing we can validate against
			// We return an empty list since this is not an error
			s.telem.Logger.WithContext(ctx).WithFields(kvp.Int64("gh.repo.id", repositoryID)).
				Info("repository not found")
			return notify.RecipientIDToReasons{}, nil
		}

		return nil, errors.Wrap(err, "error checking ignored repository").With(errors.MarkRetriable())
	}

	validatedRecipients := notify.RecipientIDToReasons{}

	removedRecipientsCount := 0
	for userID, result := range results.UserIDToCheckResult {
		if !result.IsDeliverable {
			s.telem.Logger.WithContext(ctx).
				WithFields(
					kvp.String("gh.notifyd.reason", result.NotDeliverableReason),
					kvp.Int64("gh.user.id", userID),
				).
				Info("skipping notification delivery because not passed notify policy")
			s.statter.Counter("notify", stats.Tags{"status": "skipped", "reason": strings.ReplaceAll(result.NotDeliverableReason, " ", "_")}, 1)
			removedRecipientsCount++
		} else {
			// copy and don't modify input parameter
			validatedRecipients[userID] = recipientIDsToReasons[userID]
		}
	}

	if removedRecipientsCount > 0 {
		s.telem.Logger.WithContext(ctx).Info(fmt.Sprintf("removed %d recipients from delivery batch", removedRecipientsCount))
	}

	return validatedRecipients, nil
}
