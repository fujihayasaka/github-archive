package alertlinks

import (
	"context"
	"testing"

	"github.com/github/go-http/v2/middleware/requestid"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	tshydro_entities "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0/entities"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/elasticsearch"
	mocks "github.com/github/turboscan/ts/mocks/alertlinks"
	"github.com/github/turboscan/ts/mysql/alertlink"
)

const (
	repoID        = ts.RepositoryEID(1)
	pullRequestID = ts.PullRequestEID(789)
)

var (
	ref = []byte("refs/heads/campaign-fix-1-2")
)

func TestCreateAlertLinksRef(t *testing.T) {
	_, s, publisher, ctx := testSetup(t)

	la1 := &ts.LogicalAlert{
		ID:                    ts.LogicalAlertID(18),
		Number:                uint32(101),
		StableAlertIdentifier: []byte{101},
	}
	la2 := &ts.LogicalAlert{
		ID:                    ts.LogicalAlertID(20),
		Number:                uint32(105),
		StableAlertIdentifier: []byte{105},
	}

	var actual []*tshydro.AlertLinkCreate
	publisher.EXPECT().
		AlertLinksCreateBatch(gomock.Any(), gomock.Any()).
		DoAndReturn(func(ctx context.Context, messages []*tshydro.AlertLinkCreate) error {
			// Since we don't know the ID and created_at/updated_at in advance, we need to
			// manually match the expected and actual messages.
			actual = messages

			return nil
		}).
		Times(1)

	err := s.CreateAlertLinks(ctx, repoID, []*ts.LogicalAlert{la1, la2}, 0, ref)
	require.NoError(t, err)

	expected := []*tshydro.AlertLinkCreate{
		{
			RequestId: requestid.GetGitHubRequestID(ctx),
			AlertLink: &tshydro_entities.AlertLink{
				Id:             0,
				RepositoryId:   int64(repoID),
				AlertNumber:    101,
				LogicalAlertId: 18,
				PullRequestId:  nil,
				Ref:            wrapperspb.Bytes(ref),
				CreatedAt:      nil,
				UpdatedAt:      nil,
			},
		},
		{
			RequestId: requestid.GetGitHubRequestID(ctx),
			AlertLink: &tshydro_entities.AlertLink{
				Id:             0,
				RepositoryId:   int64(repoID),
				AlertNumber:    105,
				LogicalAlertId: 20,
				PullRequestId:  nil,
				Ref:            wrapperspb.Bytes(ref),
				CreatedAt:      nil,
				UpdatedAt:      nil,
			},
		},
	}

	for _, a := range actual {
		require.Greater(t, a.AlertLink.Id, int64(0))
		require.NotNil(t, a.AlertLink.CreatedAt)
		require.NotNil(t, a.AlertLink.UpdatedAt)

		// Reset the unknown fields to their default values
		a.AlertLink.Id = 0
		a.AlertLink.CreatedAt = nil
		a.AlertLink.UpdatedAt = nil
	}

	require.ElementsMatch(t, expected, actual)
}

func TestCreateAlertLinksPullRequest(t *testing.T) {
	_, s, publisher, ctx := testSetup(t)

	la1 := &ts.LogicalAlert{
		ID:                    ts.LogicalAlertID(18),
		Number:                uint32(101),
		StableAlertIdentifier: []byte{101},
	}
	la2 := &ts.LogicalAlert{
		ID:                    ts.LogicalAlertID(20),
		Number:                uint32(105),
		StableAlertIdentifier: []byte{105},
	}

	var actual []*tshydro.AlertLinkCreate
	publisher.EXPECT().
		AlertLinksCreateBatch(gomock.Any(), gomock.Any()).
		DoAndReturn(func(ctx context.Context, messages []*tshydro.AlertLinkCreate) error {
			// Since we don't know the ID and created_at/updated_at in advance, we need to
			// manually match the expected and actual messages.
			actual = messages

			return nil
		}).
		Times(1)

	err := s.CreateAlertLinks(ctx, repoID, []*ts.LogicalAlert{la1, la2}, pullRequestID, nil)
	require.NoError(t, err)

	expected := []*tshydro.AlertLinkCreate{
		{
			RequestId: requestid.GetGitHubRequestID(ctx),
			AlertLink: &tshydro_entities.AlertLink{
				Id:             0,
				RepositoryId:   int64(repoID),
				AlertNumber:    101,
				LogicalAlertId: 18,
				PullRequestId:  wrapperspb.Int64(int64(pullRequestID)),
				Ref:            nil,
				CreatedAt:      nil,
				UpdatedAt:      nil,
			},
		},
		{
			RequestId: requestid.GetGitHubRequestID(ctx),
			AlertLink: &tshydro_entities.AlertLink{
				Id:             0,
				RepositoryId:   int64(repoID),
				AlertNumber:    105,
				LogicalAlertId: 20,
				PullRequestId:  wrapperspb.Int64(int64(pullRequestID)),
				Ref:            nil,
				CreatedAt:      nil,
				UpdatedAt:      nil,
			},
		},
	}

	for _, a := range actual {
		require.Greater(t, a.AlertLink.Id, int64(0))
		require.NotNil(t, a.AlertLink.CreatedAt)
		require.NotNil(t, a.AlertLink.UpdatedAt)

		// Reset the unknown fields to their default values
		a.AlertLink.Id = 0
		a.AlertLink.CreatedAt = nil
		a.AlertLink.UpdatedAt = nil
	}

	require.ElementsMatch(t, expected, actual)
}

func TestUpdatePRFromRef(t *testing.T) {
	db, s, publisher, ctx := testSetup(t)

	ref := []byte("refs/heads/feature1")

	alertLink := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: ts.LogicalAlertID(123),
		Ref:            ref,
	}
	err := db.Create(&alertLink).Error
	require.NoError(t, err)

	otherAlertAlertLink := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: ts.LogicalAlertID(456),
		Ref:            ref,
	}
	err = db.Create(&otherAlertAlertLink).Error
	require.NoError(t, err)

	var actual []*tshydro.AlertLinkUpdate
	publisher.EXPECT().
		AlertLinksUpdateBatch(gomock.Any(), gomock.Any()).
		DoAndReturn(func(ctx context.Context, messages []*tshydro.AlertLinkUpdate) error {
			// Since we don't know the ID and created_at/updated_at in advance, we need to
			// manually match the expected and actual messages.
			actual = messages

			return nil
		}).
		Times(1)

	updatedAlertLinksCount, err := s.UpdatePRFromRef(ctx, repoID, ref, pullRequestID)
	require.NoError(t, err)
	require.Equal(t, int64(2), updatedAlertLinksCount)

	requestID := requestid.GetGitHubRequestID(ctx)
	require.NotEmpty(t, requestID)

	expected := []*tshydro.AlertLinkUpdate{
		{
			RequestId: wrapperspb.String(requestID),
			AlertLink: &tshydro_entities.AlertLink{
				Id:             0,
				RepositoryId:   int64(repoID),
				AlertNumber:    0,
				LogicalAlertId: 123,
				PullRequestId:  wrapperspb.Int64(int64(pullRequestID)),
				Ref:            nil,
				CreatedAt:      nil,
				UpdatedAt:      nil,
			},
		},
		{
			RequestId: wrapperspb.String(requestID),
			AlertLink: &tshydro_entities.AlertLink{
				Id:             0,
				RepositoryId:   int64(repoID),
				AlertNumber:    0,
				LogicalAlertId: 456,
				PullRequestId:  wrapperspb.Int64(int64(pullRequestID)),
				Ref:            nil,
				CreatedAt:      nil,
				UpdatedAt:      nil,
			},
		},
	}

	for _, a := range actual {
		require.Greater(t, a.AlertLink.Id, int64(0))
		require.NotNil(t, a.AlertLink.CreatedAt)
		require.NotNil(t, a.AlertLink.UpdatedAt)

		// Reset the unknown fields to their default values
		a.AlertLink.Id = 0
		a.AlertLink.CreatedAt = nil
		a.AlertLink.UpdatedAt = nil
	}

	require.ElementsMatch(t, expected, actual)
}

func TestCreateAlertLinksRefUpdatesIndex(t *testing.T) {
	_, s, publisher, ctx := testSetup(t)

	la1 := &ts.LogicalAlert{
		BaseModel:             ts.BaseModel{UpdatedAt: sqltime.Now()},
		ID:                    ts.LogicalAlertID(18),
		Number:                uint32(101),
		StableAlertIdentifier: []byte{101},
	}
	la2 := &ts.LogicalAlert{
		BaseModel:             ts.BaseModel{UpdatedAt: sqltime.Now()},
		ID:                    ts.LogicalAlertID(20),
		Number:                uint32(105),
		StableAlertIdentifier: []byte{105},
	}

	repository := &ts.Repository{}
	searchDocs, err := ts.SearchDocumentsFromAlerts(repository, []*ts.LogicalAlert{la1, la2})
	require.NoError(t, err)

	err = s.es.IndexDocuments(ctx, ts.Index_OrgLevel, searchDocs)
	require.NoError(t, err)

	require.NoError(t, s.es.Refresh(ctx, ts.Index_OrgLevel))

	publisher.EXPECT().
		AlertLinksCreateBatch(gomock.Any(), gomock.Any()).
		Times(1)

	err = s.CreateAlertLinks(ctx, repoID, []*ts.LogicalAlert{la1}, 0, ref)
	require.NoError(t, err)

	require.NoError(t, s.es.Refresh(ctx, ts.Index_OrgLevel))

	updatedEsDoc1, err := s.es.GetDocument(ctx, ts.Index_OrgLevel, uint64(la1.ID))
	require.NoError(t, err)
	require.NotNil(t, updatedEsDoc1)
	require.True(t, updatedEsDoc1.HasLinks)

	updatedEsDoc2, err := s.es.GetDocument(ctx, ts.Index_OrgLevel, uint64(la2.ID))
	require.NoError(t, err)
	require.NotNil(t, updatedEsDoc2)
	require.False(t, updatedEsDoc2.HasLinks)
}

func testSetup(t *testing.T) (*gorm.DB, *Service, *mocks.MockHydroPublisher, context.Context) {
	t.Helper()

	db := dbtest.RequireConnection(t)
	alertLinkService := alertlink.NewService(db)

	mockCtrl := gomock.NewController(t)
	publisher := mocks.NewMockHydroPublisher(mockCtrl)

	s := NewService(alertLinkService, publisher, elasticsearch.SetUpTestElasticSearchService(t))

	ctx := context.Background()
	// Add a request ID to test that it is passed to the publisher
	ctx = requestid.WithNewGitHubRequestID(ctx)

	return db, s, publisher, ctx
}
