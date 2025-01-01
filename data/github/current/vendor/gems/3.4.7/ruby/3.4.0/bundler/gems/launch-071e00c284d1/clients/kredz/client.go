package kredz

import (
	"context"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/pkg/errors"

	kredzpb "github.com/github/kredz/services/protobuf/credz"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
)

const (
	KredzMaxRetries    = 3
	KredzReqRetryDelay = 200 * time.Millisecond
)

// Client is an interface to the calls made to the credz RPC server.
type Client interface {
	ListSecretsForRepository(ctx context.Context, ownerType string, ownerNextGlobalID types.GlobalID, repoID types.GlobalID, isPrivateRepo bool, appID types.GlobalID) (*RepositorySecretsResponse, error)
	DeleteSecretsForOwner(ctx context.Context, owner kredzpb.IsCredentialOwnerOwner) (*kredzpb.DeleteSecretsForOwnerResponse, error)
	ListSecretsForOwner(ctx context.Context, owner *kredzpb.CredentialOwner, appID types.GlobalID) (*ListSecretsResponse, error)
}

type RepositorySecretsResponse struct {
	RepositorySecrets   map[string]string
	OrganizationSecrets map[string]string
}

type ListSecretsResponse struct {
	Secrets map[string]string
}

type client struct {
	c          kredzpb.CredentialsService
	maxRetries uint64
	retryDelay time.Duration
}

func NewClient(svcClient kredzpb.CredentialsService, maxRetries uint64, retryDelay time.Duration) *client {
	return &client{
		c:          svcClient,
		maxRetries: maxRetries,
		retryDelay: retryDelay,
	}
}
func (c *client) DeleteSecretsForOwner(ctx context.Context, credentialOwner kredzpb.IsCredentialOwnerOwner) (*kredzpb.DeleteSecretsForOwnerResponse, error) {

	ctx, span := tracing.Start(ctx)
	defer span.End()

	delay := backoff.NewConstantBackOff(c.retryDelay)
	b := backoff.WithMaxRetries(delay, c.maxRetries)

	req := &kredzpb.DeleteSecretsForOwnerRequest{
		Owner: &kredzpb.CredentialOwner{
			Owner: credentialOwner,
		},
	}

	var res *kredzpb.DeleteSecretsForOwnerResponse
	var err error
	operation := func() error {
		res, err = c.c.DeleteSecretsForOwner(ctx, req)
		if err != nil {
			return err
		}

		return nil
	}

	err = backoff.Retry(operation, b)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "failed to delete secrets"))
	}

	return res, nil
}

func (c *client) ListSecretsForRepository(ctx context.Context, ownerType string, ownerNextGlobalID types.GlobalID, repoID types.GlobalID, isPrivateRepo bool, appID types.GlobalID) (*RepositorySecretsResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	delay := backoff.NewConstantBackOff(c.retryDelay)
	b := backoff.WithMaxRetries(delay, c.maxRetries)

	req := &kredzpb.ListSecretsForRepositoryRequest{
		Repository: &kredzpb.RepositoryWithOwner{
			Repository: &kredzpb.Repository{
				GlobalId: repoID.String(),
			},
			Owner: getRepositoryOwner(ownerType, ownerNextGlobalID),
		},
		Integration:  appID.String(),
		IsPrivate:    isPrivateRepo,
		IncludeValue: true,
	}

	var res *kredzpb.ListSecretsForRepositoryResponse
	var err error
	operation := func() error {
		res, err = c.c.ListSecretsForRepository(ctx, req)
		if err != nil {
			return err
		}

		return nil
	}

	err = backoff.Retry(operation, b)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	repositorySecrets := make(map[string]string, len(res.RepositorySecrets))
	for _, secret := range res.RepositorySecrets {
		decryptedValue := ""
		if secret.Value != nil {
			decryptedValue = string(secret.Value)
		}

		repositorySecrets[secret.Name] = decryptedValue
	}

	organizationSecrets := make(map[string]string, len(res.OrganizationSecrets))
	for _, secret := range res.OrganizationSecrets {
		decryptedValue := ""
		if secret.Value != nil {
			decryptedValue = string(secret.Value)
		}

		organizationSecrets[secret.Name] = decryptedValue
	}
	return &RepositorySecretsResponse{
		RepositorySecrets:   repositorySecrets,
		OrganizationSecrets: organizationSecrets,
	}, nil
}

func (c *client) ListSecretsForOwner(ctx context.Context, owner *kredzpb.CredentialOwner, appID types.GlobalID) (*ListSecretsResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	delay := backoff.NewConstantBackOff(c.retryDelay)
	b := backoff.WithMaxRetries(delay, c.maxRetries)

	req := &kredzpb.ListRequest{
		Owner:        owner,
		Integration:  appID.String(),
		IncludeValue: true,
	}

	var res *kredzpb.ListResponse
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

	secrets := make(map[string]string, len(res.Credentials))
	for _, secret := range res.Credentials {
		decryptedValue := ""
		if secret.Value != nil {
			decryptedValue = string(secret.Value)
		}

		secrets[secret.Name] = decryptedValue
	}

	return &ListSecretsResponse{
		Secrets: secrets,
	}, nil
}

func getRepositoryOwner(ownerType string, ownerNextGlobalID types.GlobalID) *kredzpb.CredentialOwner {
	if ownerType == "Organization" {
		org := &kredzpb.Organization{
			GlobalId: ownerNextGlobalID.String(),
		}

		return &kredzpb.CredentialOwner{
			Owner: &kredzpb.CredentialOwner_Organization{
				Organization: org,
			},
		}
	}

	return &kredzpb.CredentialOwner{
		Owner: &kredzpb.CredentialOwner_User{
			User: &kredzpb.User{
				GlobalId: ownerNextGlobalID.String(),
			},
		},
	}
}
