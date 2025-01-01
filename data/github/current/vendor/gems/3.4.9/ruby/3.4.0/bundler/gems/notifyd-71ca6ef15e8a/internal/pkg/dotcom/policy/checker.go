// Package policy implements the policy checker for service requests.
package policy

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"google.golang.org/protobuf/types/known/structpb"
	wrappers "google.golang.org/protobuf/types/known/wrapperspb"

	email "github.com/github/notifyd/internal/email/datastructures"
	api_client "github.com/github/notifyd/internal/pkg/dotcom"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/tenancy"
	notifyd "github.com/github/notifyd/proto/notifyd/v1"
)

// CheckResult represents the result of a policy check.
type CheckResult struct {
	IsDeliverable        bool
	NotDeliverableReason string
	Login                string
}

type userIDToCheckResults map[int64]CheckResult

// BatchCheckResult represents the result of a batch policy check.
type BatchCheckResult struct {
	UserIDToCheckResult       userIDToCheckResults
	NotDeliverableBatchReason string
}

// EmailDeliveryRequest is a helper struct to construct requests for email delivery
type EmailDeliveryRequest struct {
	UserID         int64
	OrganizationID int64
	NotificationID *structpb.Struct
	MatchData      *structpb.Struct
}

// Checker represents a policy checker.
type Checker interface {
	// CanDeliverPushNotification tells whether a push notification can be delivered to a user under
	// certain conditions. In case it isn't possible it tells why.
	CanDeliverPushNotification(
		ctx context.Context,
		tenant tenancy.Tenant,
		userID int64,
		skipSamlEnforcement bool,
		organizationID int64,
		oauthAccessID int64,
		reasons []string) (CheckResult, error)

	// GetDeliverEmailData tells us whether an email can be delivered to an user on an org. In
	// case the check is positive it tells to which address and returns authentication tokens for unsubscribe links and reply. It case it is negative it tells why.
	GetDeliverEmailData(ctx context.Context, tenant tenancy.Tenant, request *EmailDeliveryRequest) (email.DeliverEmailData, error)

	// BatchCheckNotifyPolicy does a batch check for a group of users on whether they can
	// receive notifications in general or not. Checks are returned as map of userID => CheckResult.
	BatchCheckNotifyPolicy(ctx context.Context, tenant tenancy.Tenant, recipients notify.RecipientIDToReasons, notifyContext *notifyd.ShouldNotifyRequestContext) (BatchCheckResult, error)

	// BatchCheckIgnoredRepository checks whether a repository has been ignored by a batch of recipients.
	// Checks are returned as map of userID => CheckResult.
	BatchCheckIgnoredRepository(ctx context.Context, tenant tenancy.Tenant, repositoryID int64, recipients notify.RecipientIDToReasons) (BatchCheckResult, error)
}

type checker struct {
	telem            *telemetry.Provider
	notifydAPIClient api_client.APIClient
}

// NewChecker creates a new policy checker.
func NewChecker(client api_client.APIClient, telem *telemetry.Provider) Checker {
	return checker{notifydAPIClient: client, telem: telem}
}

func (c checker) CanDeliverPushNotification(ctx context.Context, tenant tenancy.Tenant, userID int64, skipSamlEnforcement bool, organizationID, oauthAccessID int64, reasons []string) (CheckResult, error) {
	request := &notifyd.CheckDeliverMobilePushPolicyRequest{
		//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
		UserId:              int32(userID),
		SkipSamlEnforcement: skipSamlEnforcement,
		//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
		OrganizationId: int32(organizationID),
		OauthAccessId:  oauthAccessID,
		Reasons:        reasons,
	}
	resp, err := c.notifydAPIClient.CheckDeliverMobilePushPolicy(ctx, tenant, request)
	if err != nil {
		return CheckResult{false, "unexpected error", ""}, err
	}

	return CheckResult{resp.GetIsDeliverable(), resp.GetError(), resp.GetLogin()}, nil
}

func (c checker) GetDeliverEmailData(ctx context.Context, tenant tenancy.Tenant, request *EmailDeliveryRequest) (email.DeliverEmailData, error) {
	resp, err := c.notifydAPIClient.GetDeliverEmailData(ctx, tenant, buildDeliverEmailProto(request))
	if err != nil {
		return email.DeliverEmailData{
			IsDeliverable:        false,
			NotDeliverableReason: "unexpected error",
		}, errors.Wrap(err, "checking email policy")
	}

	return email.DeliverEmailData{
		IsDeliverable:        resp.GetIsDeliverable(),
		NotDeliverableReason: resp.GetError(),
		Email:                resp.GetEmail(),
		Login:                resp.GetLogin(),
		AuthTokens:           c.getAuthTokensFromResponse(ctx, resp),
	}, nil
}

func buildDeliverEmailProto(request *EmailDeliveryRequest) *notifyd.GetDeliverEmailDataRequest {
	return &notifyd.GetDeliverEmailDataRequest{
		//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
		UserId: int32(request.UserID),
		//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
		OrganizationId: int32(request.OrganizationID),
		AuthTokenRequests: []*notifyd.AuthTokenRequest{
			{
				Scope: email.MuteAuthScope,
				Data:  request.MatchData,
			},
			{
				Scope: email.MuteListScope,
				Data:  request.MatchData,
			},
			{
				Scope: email.EmailReplyScope,
				Data:  request.NotificationID,
			},
		}}
}

// getAuthTokensFromResponse deserializes the tokens from the response, in addition to that, and as a
// temporary measure, it logs the size of each token.
//
// We do that as we want to know how big tokens are to understand how big of a problem this is in
// the context of https://github.com/github/notifyd/issues/1851
func (c checker) getAuthTokensFromResponse(ctx context.Context, resp *notifyd.GetDeliverEmailDataResponse) []email.AuthToken {
	var tokens []email.AuthToken
	for _, rawToken := range resp.AuthTokens {
		token := email.AuthToken{
			Scope: rawToken.Scope,
			Token: rawToken.Token,
		}
		tokens = append(tokens, token)
		c.telem.Logger.WithContext(ctx).
			WithFields(
				kvp.String("gh.notifyd.authtoken.scope", token.Scope),
				kvp.Int("gh.notifyd.authtoken.size", len(token.Token))).
			Info("auth token")
	}

	return tokens
}

func (c checker) BatchCheckNotifyPolicy(ctx context.Context, tenant tenancy.Tenant, recipientIDsToReasons notify.RecipientIDToReasons, notifyContext *notifyd.ShouldNotifyRequestContext) (BatchCheckResult, error) {
	recipients := make([]*notifyd.Recipient, 0, len(recipientIDsToReasons))
	for recipientID, reasons := range recipientIDsToReasons {
		rr := make([]*notifyd.Reason, len(reasons))
		for i, reason := range reasons {
			rr[i] = &notifyd.Reason{Name: reason}
		}

		r := &notifyd.Recipient{
			//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
			UserId:  int32(recipientID),
			Reasons: rr,
		}

		recipients = append(recipients, r)
	}

	request := &notifyd.BatchCheckNotifyPolicyRequest{
		Context:    notifyContext,
		Recipients: recipients,
	}

	checkPolicyResults := make(map[int64]CheckResult)

	resp, err := c.notifydAPIClient.BatchCheckNotifyPolicy(ctx, tenant, request)
	if err != nil {
		return BatchCheckResult{checkPolicyResults, "unexpected error"}, err
	}

	for _, receivedPolicyCheckResult := range resp.Responses {
		checkPolicyResults[int64(receivedPolicyCheckResult.UserId)] = CheckResult{
			receivedPolicyCheckResult.Notify,
			receivedPolicyCheckResult.Error,
			"",
		}
	}

	return BatchCheckResult{checkPolicyResults, ""}, nil
}

func (c checker) BatchCheckIgnoredRepository(ctx context.Context, tenant tenancy.Tenant, repositoryID int64, recipientIDsToReasons notify.RecipientIDToReasons) (BatchCheckResult, error) {
	recipients := make([]*notifyd.Recipient, 0, len(recipientIDsToReasons))
	for recipientID, reasons := range recipientIDsToReasons {
		rr := make([]*notifyd.Reason, len(reasons))
		for i, reason := range reasons {
			rr[i] = &notifyd.Reason{Name: reason}
		}

		r := &notifyd.Recipient{
			//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
			UserId:  int32(recipientID),
			Reasons: rr,
		}

		recipients = append(recipients, r)
	}

	request := &notifyd.BatchCheckIgnoredRepositoryRequest{
		RepositoryId: &wrappers.Int64Value{Value: repositoryID},
		Recipients:   recipients,
	}

	results := make(map[int64]CheckResult)

	resp, err := c.notifydAPIClient.BatchCheckIgnoredRepository(ctx, tenant, request)
	if err != nil {
		return BatchCheckResult{results, "unexpected error"}, err
	}

	for _, result := range resp.Responses {
		results[int64(result.UserId)] = CheckResult{
			result.Notify,
			result.Error,
			"",
		}
	}

	return BatchCheckResult{results, ""}, nil
}
