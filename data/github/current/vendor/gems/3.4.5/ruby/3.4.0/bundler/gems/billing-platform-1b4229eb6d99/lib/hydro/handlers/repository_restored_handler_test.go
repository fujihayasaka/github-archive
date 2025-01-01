package handlers

import (
	"context"
	"errors"
	"testing"

	"github.com/github/billing-platform/internal/monolith"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"

	repositories "github.com/github/monolith-twirp-billing/repositories/v1"
)

func Test_RepositoryRestoredHandler_Updates_Repo_Metadata(t *testing.T) {
	mocker := pegomock.WithT(t)
	mockDB := fakes.NewMockDatabase(mocker)
	mockRepoAPI := fakes.NewMockRepositoryAPI(mocker)
	mockMonolithClient := monolith.Client{
		RepositoryAPI: mockRepoAPI,
	}

	handler := RepositoryRestoredHandler{
		DB:             mockDB,
		MonolithClient: &mockMonolithClient,
	}

	pegomock.When(mockMonolithClient.RepositoryAPI.GetRepositoryMetadata(pegomock.Any[context.Context](), pegomock.Any[*repositories.GetRepositoryMetadataRequest]())).ThenReturn(
		&repositories.GetRepositoryMetadataResponse{
			Repository: &repositories.Repository{
				Id:       1,
				IsPublic: true,
			},
		}, nil,
	)

	envelope, err := stubs.CreateEnvelopeForRepositoryRestoredEvent(1)
	assert.NoError(t, err)

	err = handler.HandleEnvelope(context.Background(), log.NewNullLogger(), envelope)
	assert.NoError(t, err)

	mockRepoAPI.VerifyWasCalledOnce().GetRepositoryMetadata(
		pegomock.Any[context.Context](),
		pegomock.Eq(
			&repositories.GetRepositoryMetadataRequest{Id: 1},
		),
	)
	mockDB.VerifyWasCalledOnce().UpsertWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq[models.ItemKey](
			models.NewRepo(1, true),
		),
		pegomock.Any[*interfaces.QueryOptions](),
	)
}

func Test_RepositoryRestoredHandler_Error(t *testing.T) {
	mocker := pegomock.WithT(t)
	mockDB := fakes.NewMockDatabase(mocker)
	mockRepoAPI := fakes.NewMockRepositoryAPI(mocker)
	mockMonolithClient := monolith.Client{
		RepositoryAPI: mockRepoAPI,
	}

	handler := RepositoryRestoredHandler{
		DB:             mockDB,
		MonolithClient: &mockMonolithClient,
	}

	pegomock.When(mockMonolithClient.RepositoryAPI.GetRepositoryMetadata(pegomock.Any[context.Context](), pegomock.Any[*repositories.GetRepositoryMetadataRequest]())).ThenReturn(
		nil,
		errors.New("error"),
	)

	envelope, err := stubs.CreateEnvelopeForRepositoryRestoredEvent(1)
	assert.NoError(t, err)

	err = handler.HandleEnvelope(context.Background(), log.NewNullLogger(), envelope)
	assert.Error(t, err)

	mockRepoAPI.VerifyWasCalledOnce().GetRepositoryMetadata(
		pegomock.Any[context.Context](),
		pegomock.Eq(
			&repositories.GetRepositoryMetadataRequest{Id: 1},
		),
	)
	mockDB.VerifyWasCalled(pegomock.Never()).UpsertWithOptions(
		pegomock.Any[context.Context](),
		pegomock.Any[log.Logger](),
		pegomock.Eq[models.ItemKey](
			models.NewRepo(1, true),
		),
		pegomock.Any[*interfaces.QueryOptions](),
	)
}
