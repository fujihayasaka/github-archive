// Package auth implements the authzd authorizor.
package auth

import (
	"context"
	"time"

	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/github/authzd/pkg/client"
	authzd_pb "github.com/github/authzd/pkg/proto"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/http"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// AuthzdClient represents a client for the authzd service.
type AuthzdClient interface {
	Authorize(context.Context, tenancy.Tenant, *authzd_pb.Request) (*authzd_pb.Decision, error)
	BatchAuthorize(context.Context, tenancy.Tenant, *authzd_pb.BatchRequest) (*authzd_pb.BatchDecision, error)
}

type apiClient struct {
	twirp authzd_pb.Authorizer
}

// Authorize makes an authorization request.
func (c *apiClient) Authorize(ctx context.Context, tenant tenancy.Tenant, req *authzd_pb.Request) (*authzd_pb.Decision, error) {
	return c.twirp.Authorize(tenancy.ContextWithTenant(ctx, tenant), req)
}

// BatchAuthorize makes a batch authorization request.
func (c *apiClient) BatchAuthorize(ctx context.Context, tenant tenancy.Tenant, req *authzd_pb.BatchRequest) (*authzd_pb.BatchDecision, error) {
	return c.twirp.BatchAuthorize(tenancy.ContextWithTenant(ctx, tenant), req)
}

// Authorizer represents an authorizer.
type Authorizer interface {
	AuthorizeRecipients(ctx context.Context, tenant tenancy.Tenant, initiatorID int64, recipients []int64, attributes []*anypb.Any) (PolicyCheckLookup, error)
}

// AuthzdAuthorizer represents an authzd authorizer.
type AuthzdAuthorizer struct {
	client AuthzdClient
}

// UnauthorizedLookup is a map.
type UnauthorizedLookup map[int64]string

// CheckStatus represents a policy check status.
type CheckStatus byte

// CheckStatus values.
const (
	Allow CheckStatus = iota
	Deny
)

// PolicyCheck represents a policy check.
type PolicyCheck struct {
	UserID int64
	Status CheckStatus
	Reason string
}

// IsAllowed returns true if the policy check is allowed.
func (p PolicyCheck) IsAllowed() bool {
	return p.Status == Allow
}

// PolicyCheckLookup is a list of policy checks.
type PolicyCheckLookup []PolicyCheck

// NewAuthzdAuthorizer creates a new authzd authorizer.
func NewAuthzdAuthorizer(url string, statter stats.Client, telem *telemetry.Provider) (*AuthzdAuthorizer, error) {
	// Authzd has a timeout of 5 seconds. The client we use will retry after that, we've seen cases
	// where network issues where keeping requests stuck for up to 2 minutes on GLB and we want to
	// avoid that.
	httpClient := http.NewClient(http.WithRetryTimeout(6*time.Second), http.WithLogger(telem.Logger))
	tenantClient := tenancy.NewForwarder(httpClient)
	authzdClient, err := client.New(url,
		client.WithHTTPClient(tenantClient),
		client.WithUserAgent("notifyd"),
		client.WithStatter(statter, "notifyd"),
		client.WithRequestIDForwarder(),
	)
	if err != nil {
		return nil, err
	}

	wrapped := &apiClient{twirp: authzdClient}

	return &AuthzdAuthorizer{client: wrapped}, nil
}

// AuthorizeRecipients runs notification policy checks on each recipient of a notification.
// These policy checks use
//   - An initiatorID (the notification initiator) to verify that the recipient can receive notifications from the actor
//   - A set of common attributes derived from the notification itself
//
// NOTE: From the Notifications point of view, an Actor is the entity (User, Bot, etc) that initiates a notification
// (adds a comment, CI build, etc). A recipient is the user that could receive such notification.
// From Authzd point of view, an Actor is the entity on which the policy checks are done. Since this method
// checks policies over recipients (users), the Actor used in Authzd attributes is the recipient,
// and the Notification's Actor is the `notification.initiator`.
func (a *AuthzdAuthorizer) AuthorizeRecipients(ctx context.Context, tenant tenancy.Tenant, initiatorID int64, recipients []int64, commonAttributes []*anypb.Any) (PolicyCheckLookup, error) {
	attributes := []*authzd_pb.Attribute{
		{
			Id:    "version",
			Value: authzd_pb.NewInt64Value(2),
		},
		{
			Id:    "action",
			Value: authzd_pb.NewStringValue("receive_notification"),
		},
		{
			Id: "actor.type",
			// NOTE: We don't exactly know at this point what kind of user is this (User, Bor or Organization)
			// but we need to set this attribute in order to make authzd to work. It will deny the request
			// if is not present.
			// The policy will ensure the right type of user will be allowed.
			Value: authzd_pb.NewStringValue("User"),
		},
		{
			Id:    "notification.initiator.id",
			Value: authzd_pb.NewInt64Value(initiatorID),
		},
	}

	for _, wrapped := range commonAttributes {
		var attribute authzd_pb.Attribute
		err := proto.Unmarshal(wrapped.GetValue(), &attribute)

		if err != nil {
			return nil, errors.Wrap(err, "unmarshalling authzd attribute")
		}

		if attribute.GetId() != "actor.id" && attribute.GetId() != "action" {
			attributes = append(attributes, &attribute)
		}
	}

	requests := make([]*authzd_pb.Request, len(recipients))

	for idx, userID := range recipients {
		requestAttributes := make([]*authzd_pb.Attribute, len(attributes)+1)
		copy(requestAttributes, attributes)
		requestAttributes[len(requestAttributes)-1] = &authzd_pb.Attribute{
			Id:    "actor.id",
			Value: authzd_pb.NewInt64Value(userID),
		}
		request := authzd_pb.Request{
			Attributes: requestAttributes,
		}
		requests[idx] = &request
	}

	batchRequest := authzd_pb.BatchRequest{Requests: requests}
	decisions, err := a.client.BatchAuthorize(ctx, tenant, &batchRequest)
	if err != nil {
		return nil, errors.Wrap(err, "request to authzd")
	}

	var checks []PolicyCheck

	for idx, decision := range decisions.GetDecisions() {
		var check PolicyCheck
		if decision.Result != authzd_pb.Result_ALLOW {
			check = PolicyCheck{UserID: recipients[idx], Status: Deny, Reason: decision.GetReason()}
		} else {
			check = PolicyCheck{UserID: recipients[idx], Status: Allow}
		}

		checks = append(checks, check)
	}

	return checks, nil
}
