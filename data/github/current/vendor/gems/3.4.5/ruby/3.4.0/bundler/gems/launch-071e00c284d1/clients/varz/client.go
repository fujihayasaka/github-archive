package varz

import (
	"context"
	"fmt"
	"time"

	"github.com/cenkalti/backoff/v4"

	varzpb "github.com/github/kredz/services/protobuf/varz"

	"github.com/github/kredz/utils/varzconstants"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
)

const (
	VarzMaxRetries    = 3
	VarzReqRetryDelay = 200 * time.Millisecond
)

// Client is an interface to the calls made to the varz RPC server.
type Client interface {
	ListVariablesForRepository(ctx context.Context, owner types.WorkflowInvocationOwner, ownerGlobalID types.GlobalID, repoID types.GlobalID, isPrivateRepo bool, appID types.GlobalID, includeRemainingVariableNames bool) (*RepositoryVariablesResponse, error)
	ListVariablesForOwner(ctx context.Context, owner *varzpb.VariableOwner, appID types.GlobalID) (*ListVariablesResponse, error)
	ListVariablesByNamesForOwner(ctx context.Context, owner *varzpb.VariableOwner, appID types.GlobalID, variableNames []string) (*ListVariablesResponse, error)
	ListOrganizationVariablesForRepositoryByNames(ctx context.Context, ownerGlobalID types.GlobalID, ownerType string, repoID types.GlobalID, isPrivateRepo bool, appID types.GlobalID, variableNames []string) (*ListVariablesResponse, error)
}

type RepositoryVariablesResponse struct {
	RepositoryVariables                 map[string]string
	OrganizationVariables               map[string]string
	RemainingRepositoryVariablesNames   []string
	RemainingOrganizationVariablesNames []string
}

type ListVariablesResponse struct {
	Variables map[string]string
}

type client struct {
	c          varzpb.VariablesService
	maxRetries uint64
	retryDelay time.Duration
}

func NewClient(svcClient varzpb.VariablesService, maxRetries uint64, retryDelay time.Duration) *client {
	return &client{
		c:          svcClient,
		maxRetries: maxRetries,
		retryDelay: retryDelay,
	}
}

func (c *client) ListVariablesForRepository(ctx context.Context, owner types.WorkflowInvocationOwner, ownerGlobalID types.GlobalID, repoID types.GlobalID, isPrivateRepo bool, appID types.GlobalID, includeRemainingVariableNames bool) (*RepositoryVariablesResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	delay := backoff.NewConstantBackOff(c.retryDelay)
	b := backoff.WithMaxRetries(delay, c.maxRetries)

	req := &varzpb.ListVariablesForRepositoryRequest{
		Repository: &varzpb.RepositoryWithOwner{
			Repository: &varzpb.Repository{
				GlobalId: repoID.String(),
			},
			Owner: getRepositoryOwner(owner, ownerGlobalID),
		},
		IntegrationGlobalId:           appID.String(),
		IsPrivate:                     isPrivateRepo,
		IncludeValue:                  true,
		IncludeRemainingVariableNames: includeRemainingVariableNames,
	}

	var res *varzpb.ListVariablesForRepositoryResponse
	var err error
	operation := func() error {
		res, err = c.c.ListVariablesForRepository(ctx, req)
		if err != nil {
			return err
		}

		return nil
	}

	err = backoff.Retry(operation, b)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	repositoryVariables := make(map[string]string, len(res.RepositoryVariables))
	for _, variable := range res.RepositoryVariables {
		if variable.Value != nil {
			repositoryVariables[variable.Name] = string(variable.Value)
		}
	}

	organizationVariables := make(map[string]string, len(res.OrganizationVariables))
	for _, variable := range res.OrganizationVariables {
		if variable.Value != nil {
			organizationVariables[variable.Name] = string(variable.Value)
		}
	}

	return &RepositoryVariablesResponse{
		RepositoryVariables:                 repositoryVariables,
		OrganizationVariables:               organizationVariables,
		RemainingRepositoryVariablesNames:   res.RemainingRepoVarNames,
		RemainingOrganizationVariablesNames: res.RemainingOrgVarNames,
	}, nil
}

func (c *client) ListVariablesForOwner(ctx context.Context, owner *varzpb.VariableOwner, appID types.GlobalID) (*ListVariablesResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	delay := backoff.NewConstantBackOff(c.retryDelay)
	b := backoff.WithMaxRetries(delay, c.maxRetries)

	req := &varzpb.ListRequest{
		Owner:               owner,
		IntegrationGlobalId: appID.String(),
		IncludeValue:        true,
	}

	var res *varzpb.ListResponse
	var err error
	operation := func() error {
		res, err = c.c.List(ctx, req)
		if err != nil {
			return err
		}

		return nil
	}

	err = backoff.Retry(operation, b)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	variables := make(map[string]string, len(res.Variables))
	for _, variable := range res.Variables {
		if variable.Value != nil {
			variables[variable.Name] = string(variable.Value)
		}
	}

	return &ListVariablesResponse{
		Variables: variables,
	}, nil
}

func (c *client) ListVariablesByNamesForOwner(ctx context.Context, owner *varzpb.VariableOwner, appID types.GlobalID, variableNames []string) (*ListVariablesResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if len(variableNames) > int(varzconstants.MaxNamedVariablesInputCount) {
		return nil, fmt.Errorf("Input variable name count: %d, exceeds max allowed count %d ", len(variableNames), int(varzconstants.MaxNamedVariablesInputCount))
	}

	delay := backoff.NewConstantBackOff(c.retryDelay)
	b := backoff.WithMaxRetries(delay, c.maxRetries)

	req := &varzpb.ListByNamesRequest{
		Owner:               owner,
		IntegrationGlobalId: appID.String(),
		Names:               variableNames,
	}

	var res *varzpb.ListByNamesResponse
	operation := func() error {
		var err error
		res, err = c.c.ListByNames(ctx, req)
		if err != nil {
			return err
		}

		return nil
	}

	err := backoff.Retry(operation, b)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	variables := make(map[string]string, len(res.Variables))
	for _, variable := range res.Variables {
		if variable.Value != nil {
			variables[variable.Name] = string(variable.Value)
		}
	}

	return &ListVariablesResponse{
		Variables: variables,
	}, nil
}

func (c *client) ListOrganizationVariablesForRepositoryByNames(ctx context.Context, ownerGlobalID types.GlobalID, ownerType string, repoID types.GlobalID, isPrivateRepo bool, appID types.GlobalID, variableNames []string) (*ListVariablesResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if len(variableNames) > int(varzconstants.MaxNamedVariablesInputCount) {
		return nil, fmt.Errorf("Input variable name count: %d, exceeds max allowed count %d ", len(variableNames), int(varzconstants.MaxNamedVariablesInputCount))
	}

	delay := backoff.NewConstantBackOff(c.retryDelay)
	b := backoff.WithMaxRetries(delay, c.maxRetries)
	wfInvocationOwner := types.WorkflowInvocationOwner{
		Type: ownerType,
	}
	req := &varzpb.ListOrganizationVariablesForRepositoryByNamesRequest{
		Repository: &varzpb.RepositoryWithOwner{
			Repository: &varzpb.Repository{
				GlobalId: repoID.String(),
			},
			Owner: getRepositoryOwner(wfInvocationOwner, ownerGlobalID),
		},
		IntegrationGlobalId: appID.String(),
		IsPrivate:           isPrivateRepo,
		Names:               variableNames,
	}

	var res *varzpb.ListOrganizationVariablesForRepositoryByNamesResponse
	operation := func() error {
		var err error
		res, err = c.c.ListOrganizationVariablesForRepositoryByNames(ctx, req)
		if err != nil {
			return err
		}

		return nil
	}

	err := backoff.Retry(operation, b)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	organizationVariables := make(map[string]string, len(res.OrganizationVariables))
	for _, variable := range res.OrganizationVariables {
		if variable.Value != nil {
			organizationVariables[variable.Name] = string(variable.Value)
		}
	}

	return &ListVariablesResponse{
		Variables: organizationVariables,
	}, nil
}

func getRepositoryOwner(owner types.WorkflowInvocationOwner, ownerGlobalID types.GlobalID) *varzpb.VariableOwner {
	if owner.Type == "Organization" {
		org := &varzpb.Organization{
			GlobalId: ownerGlobalID.String(),
		}

		return &varzpb.VariableOwner{
			Owner: &varzpb.VariableOwner_Organization{
				Organization: org,
			},
		}
	}

	return &varzpb.VariableOwner{
		Owner: &varzpb.VariableOwner_User{
			User: &varzpb.User{
				GlobalId: ownerGlobalID.String(),
			},
		},
	}
}
