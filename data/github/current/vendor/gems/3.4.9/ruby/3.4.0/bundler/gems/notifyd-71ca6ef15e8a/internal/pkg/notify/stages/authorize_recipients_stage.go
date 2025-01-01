package stages

import (
	"context"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/notify/auth"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

type authorizeRecipientsStage struct {
	authorizer auth.Authorizer
	clock      clockpkg.Clock
	telem      *telemetry.Provider
	statter    stats.Client
}

// NewAuthorizeRecipientsStage creates a new authorize recipients stage.
func NewAuthorizeRecipientsStage(authorizer auth.Authorizer, clock clockpkg.Clock, telem *telemetry.Provider, statter stats.Client) IAuthorizeRecipientsStage {
	return &authorizeRecipientsStage{
		authorizer: authorizer,
		clock:      clock,
		telem:      telem,
		statter:    statter,
	}
}

// AuthorizeRecipients returns the list of recipients authorized by the next version of policies
func (s *authorizeRecipientsStage) AuthorizeRecipients(
	ctx context.Context,
	tenant tenancy.Tenant,
	recipientIDsToReasons notify.RecipientIDToReasons,
	msg *notify.Notification,
) (notify.RecipientIDToReasons, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	start := s.clock.Now()
	defer func() {
		s.statter.DistributionMs(statsTimingKey, stats.Tags{"stage": "authorize_recipients", "policies_version": "2"}, s.clock.Since(start))
	}()

	actorID := msg.ActorID
	ctx = o11y.CtxSetActorID(ctx, actorID)

	logger := s.telem.Logger.WithContext(ctx).WithFields(
		kvp.Int("gh.notifyd.recipients_to_authorize_count", len(recipientIDsToReasons)),
		kvp.Int("gh.notifyd.policies.version", 2),
	)
	logger.Info("authorizing recipients")

	recipients := make([]int64, len(recipientIDsToReasons))
	idx := 0
	for userID := range recipientIDsToReasons {
		recipients[idx] = userID
		idx++
	}

	policyChecks, err := s.authorizer.AuthorizeRecipients(ctx, tenant, actorID, recipients, msg.AuthzdAttributes())
	if err != nil {
		return nil, errors.Wrap(err, "authorizing recipients").With(errors.MarkRetriable())
	}

	result := notify.RecipientIDToReasons{}
	for _, check := range policyChecks {
		if check.IsAllowed() {
			result[check.UserID] = recipientIDsToReasons[check.UserID]
		} else {
			logger.WithFields(
				kvp.Int64("gh.user.id", check.UserID),
				kvp.String("gh.notifyd.authzd.reason", check.Reason),
			).Info(
				"skipping notification delivery for unauthorized recipient")
			s.statter.Counter("notify", stats.Tags{"status": "skipped", "reason": "unauthorized_recipient", "policies_version": "2"}, 1)
		}
	}

	return result, nil
}
