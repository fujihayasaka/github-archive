package authzd

import (
	"context"
	"fmt"
	"net/http"

	authzdclient "github.com/github/authzd/pkg/client"
	authzpb "github.com/github/authzd/pkg/proto"
	errs "github.com/pkg/errors"
	circuit "github.com/rubyist/circuitbreaker"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/observability"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ahttp"
)

const (
	// string constants for authzd request
	AuthzdActorType           = "actor.type"
	AuthzdActorID             = "actor.id"
	AuthzdActorRepositoryID   = "actor.repository.id"
	AuthzdSubjectType         = "subject.type"
	AuthzdSubjectRepositoryID = "subject.repository.id"
	AuthzdAction              = "action"
	AuthzdVersion             = "version"
	Repository                = "Repository"
	UseCallableWorkflow       = "use_callable_workflow"
)

type Config struct {
	AuthzdURL    string
	BuildVersion string
	ServiceName  string
}

type RepositoryParam struct {
	ID   uint64
	Name string
}

type Client interface {
	Authorize(ctx context.Context, callerRepoID, calledRepoID uint64) (bool, error)
	InvokeAuthorize(ctx context.Context, req *authzpb.Request) (bool, error)
	BatchAuthorizeAndReturnInaccessibleRepos(ctx context.Context, callerRepoID uint64, calledRepos []*RepositoryParam) (bool, []string, error)
	BatchAuthorize(ctx context.Context, callerRepoID uint64, calledRepos []*RepositoryParam) (*authzpb.BatchDecision, error)
}

type client struct {
	authzClient authzpb.Authorizer
	obs         *observability.Observability
}

func NewClient(cfg Config, obs *observability.Observability, breaker *circuit.Breaker, innerHTTPClient *http.Client, twirpClientOpts []twirp.ClientOption) (Client, error) {
	clientID := fmt.Sprintf("%s/%s", cfg.ServiceName, cfg.BuildVersion)
	httpClient := ahttp.NewRetryClient(breaker, obs.Statter, innerHTTPClient, "authzd")
	authzdClient, err := authzdclient.New(cfg.AuthzdURL,
		authzdclient.WithUserAgent(clientID),
		authzdclient.WithRequestIDForwarder(),
		authzdclient.WithHTTPClient(httpClient),
		authzdclient.WithTwirpClientOptions(twirpClientOpts...),
	)
	if err != nil {
		return nil, errs.Wrap(err, "creating authzd client")
	}

	return &client{
		authzClient: authzdClient,
		obs:         obs,
	}, nil
}

func NewTestClient(authzStubClient authzpb.Authorizer, obs *observability.Observability) Client {
	return &client{
		authzClient: authzStubClient,
		obs:         obs,
	}
}

func (c *client) Authorize(ctx context.Context, callerRepoID, calledRepoID uint64) (bool, error) {
	req := newAuthzdIsRepoCallableRequest(int64(callerRepoID), int64(calledRepoID))
	return c.InvokeAuthorize(ctx, req)
}

func (c *client) InvokeAuthorize(ctx context.Context, req *authzpb.Request) (bool, error) {
	decision, err := c.authzClient.Authorize(ctx, req)
	if err != nil {
		return false, errs.Wrap(err, "authorizing access permission")
	}
	if decision.Result != authzpb.Result_ALLOW {
		return false, nil
	}

	return true, nil
}

func (c *client) BatchAuthorizeAndReturnInaccessibleRepos(ctx context.Context, callerRepoID uint64, calledRepos []*RepositoryParam) (bool, []string, error) {
	batchDecision, err := c.BatchAuthorize(ctx, callerRepoID, calledRepos)
	if err != nil {
		return false, nil, errs.Wrap(err, "authorizing access permission")
	}

	var inaccessibleRepos []string
	for i, decision := range batchDecision.Decisions {
		if decision.Result != authzpb.Result_ALLOW {
			inaccessibleRepos = append(inaccessibleRepos, calledRepos[i].Name)
		}
	}

	if len(inaccessibleRepos) > 0 {
		return false, inaccessibleRepos, terrors.NewForbiddenInternalActionError(inaccessibleRepos)
	}

	return true, nil, nil
}

func (c *client) BatchAuthorize(ctx context.Context, callerRepoID uint64, calledRepos []*RepositoryParam) (*authzpb.BatchDecision, error) {
	var requests []*authzpb.Request
	for _, calledRepo := range calledRepos {
		request := newAuthzdIsRepoCallableRequest(int64(callerRepoID), int64(calledRepo.ID))
		requests = append(requests, request)
	}

	batchRequest := &authzpb.BatchRequest{
		Requests: requests,
	}

	batchDecision, err := c.authzClient.BatchAuthorize(ctx, batchRequest)
	if err != nil {
		return nil, errs.Wrap(err, "failed to get permissions from authz")
	}
	return batchDecision, err
}

func newAuthzdIsRepoCallableRequest(callerRepoID, calledRepoID int64) *authzpb.Request {
	req := &authzpb.Request{
		Attributes: []*authzpb.Attribute{
			{
				Id:    AuthzdActorID,
				Value: authzpb.NewInt64Value(callerRepoID),
			},
			{
				Id:    AuthzdActorRepositoryID,
				Value: authzpb.NewInt64Value(callerRepoID),
			},
			{
				Id:    AuthzdActorType,
				Value: authzpb.NewStringValue(Repository),
			},
			{
				Id:    AuthzdSubjectRepositoryID,
				Value: authzpb.NewInt64Value(calledRepoID),
			},
			{
				Id:    AuthzdSubjectType,
				Value: authzpb.NewStringValue(Repository),
			},
			{
				Id:    AuthzdAction,
				Value: authzpb.NewStringValue(UseCallableWorkflow),
			},
		},
	}
	return req
}

func NewNullClient() Client {
	return &NullAuthzClient{}
}

// No-op authz client
type NullAuthzClient struct{}

func (c *NullAuthzClient) Authorize(_ context.Context, _, _ uint64) (bool, error) {
	return false, nil
}

func (c *NullAuthzClient) InvokeAuthorize(_ context.Context, _ *authzpb.Request) (bool, error) {
	return false, nil
}

func (c *NullAuthzClient) BatchAuthorizeAndReturnInaccessibleRepos(_ context.Context, _ uint64, _ []*RepositoryParam) (bool, []string, error) {
	return false, nil, nil
}

func (c *NullAuthzClient) BatchAuthorize(_ context.Context, _ uint64, _ []*RepositoryParam) (*authzpb.BatchDecision, error) {
	return nil, nil
}
