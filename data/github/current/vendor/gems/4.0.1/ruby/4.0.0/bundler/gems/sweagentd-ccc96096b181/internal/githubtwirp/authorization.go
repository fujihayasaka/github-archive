package githubtwirp

import (
	"context"
	"fmt"
	"strings"

	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/google/uuid"
)

// HasAccessCheck represents a single access check to be performed against the Twirp authz API.
type HasAccessCheck struct {
	// An action that should be checked. These actions are defined in
	// https://github.com/github/github/blob/HEAD/config/access_control
	Action string
	// The ID resource to check access against. This is a dotcom model's numeric ID.
	ResourceId int64
	// The type of resource to check access against. This should map to a Rails model,
	// like Repository or Organization.
	ResourceType string
	// Optional: Specify an organization ID, for checks that require it.
	OrganizationID int64
	// Optional: Specify a repository ID, for checks that require it.
	RepositoryID int64
	// Optional: Specify a repository NWO (name with owner), for checks that require it.
	RepositoryNWO string
}

// TokenHasAccess takes in a user + token and a set of access checks to perform and returns true if they all pass.
func (c *Client) TokenHasAccess(ctx context.Context, userInfo *requestctx.UserInfo, reqs []*HasAccessCheck) (bool, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "githubtwirp.Client.TokenHasAccess")
	defer span.End()

	// We want to guard against checking empty permissions so error in this case
	if len(reqs) == 0 {
		return false, goerrors.Errorf("no access checks provided to verify")
	}

	logger := c.obsv.Logger.WithContext(ctx)

	reqObjs := make([]*coreTwirp.AuthorizationRequestObject, len(reqs))
	for i, req := range reqs {
		reqObjs[i] = &coreTwirp.AuthorizationRequestObject{
			Id:             fmt.Sprintf("%s-%s-%s", req.Action, req.ResourceType, uuid.NewString()),
			Action:         req.Action,
			ResourceId:     req.ResourceId,
			ResourceType:   req.ResourceType,
			OrganizationId: req.OrganizationID,
			RepositoryId:   req.RepositoryID,
			RepositoryNwo:  req.RepositoryNWO,
		}
	}
	batch := &coreTwirp.BatchControlAccessRequest{
		AccessToken:           userInfo.TokenInfo.Token,
		AuthorizationRequests: reqObjs,
		RequestIp:             userInfo.RequestIP,
	}

	api := c.AuthorizationAPI()
	result, err := api.BatchControlAccess(ctx, batch)
	if err != nil {
		return false, goerrors.Errorf("failed to check access: %w", err)
	}
	// We want to know if all of the checks passed in where successful, so
	// iterate through each "decision" as to whether the check passed and
	// return false if any one of them failed, otherwise return true.
	var failedActions []string
	for i, decision := range result.Decisions {
		if !decision.GetDecision() {
			action := "unknown"
			if i < len(reqs) {
				action = reqs[i].Action
			}
			failedActions = append(failedActions, action)
		}
	}

	if len(failedActions) > 0 {
		logger.WithFields(
			kvp.String("failed_actions", strings.Join(failedActions, ",")),
			kvp.Int("total_checks", len(reqs)),
			kvp.Int("failed_checks", len(failedActions)),
		).Warn("token access check failed for specific actions")
		return false, nil
	}

	return true, nil
}
