package consumers

import (
	"context"
	"testing"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	tshydro_entities "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0/entities"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/alertlinks"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/elasticsearch"
	mocks "github.com/github/turboscan/ts/mocks/alertlinks"
	"github.com/github/turboscan/ts/mysql/alertlink"

	"github.com/github/turboscan/ts/hydro/topics"
)

func TestAlertLinkProcessor_PullRequestCreate_NoAlertLinks(t *testing.T) {
	_, als, _ := alertLinkProcessorTestSetup(t)

	p := NewAlertLinkProcessor(als)

	msg := createPullRequestCreateTestMessage()
	requireProcessEnvelope(t, p, msg, topics.PullRequestCreate)
}

func TestAlertLinkProcessor_PullRequestCreate_MatchingAlertLinks(t *testing.T) {
	db, als, publisher := alertLinkProcessorTestSetup(t)

	p := NewAlertLinkProcessor(als)

	msg := createPullRequestCreateTestMessage()

	repoID := msg.Repository.Id
	ref := append([]byte("refs/heads/"), msg.PullRequest.HeadBranch...)
	pullRequestID := ts.PullRequestEID(msg.PullRequest.Id)

	alertLink := ts.AlertLink{
		RepositoryID:   ts.RepositoryEID(repoID),
		LogicalAlertID: ts.LogicalAlertID(123),
		Ref:            ref,
	}
	err := db.Create(&alertLink).Error
	require.NoError(t, err)

	otherAlertAlertLink := ts.AlertLink{
		RepositoryID:   ts.RepositoryEID(repoID),
		LogicalAlertID: ts.LogicalAlertID(456),
		Ref:            ref,
	}
	err = db.Create(&otherAlertAlertLink).Error
	require.NoError(t, err)

	otherRefAlertLink := ts.AlertLink{
		RepositoryID:   ts.RepositoryEID(repoID),
		LogicalAlertID: ts.LogicalAlertID(456),
		Ref:            []byte("refs/heads/something-else"),
	}
	err = db.Create(&otherRefAlertLink).Error
	require.NoError(t, err)

	otherRepoAlertLink := ts.AlertLink{
		RepositoryID:   ts.RepositoryEID(repoID) + 53,
		LogicalAlertID: ts.LogicalAlertID(789),
		Ref:            ref,
	}
	err = db.Create(&otherRepoAlertLink).Error
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

	requireProcessEnvelope(t, p, msg, topics.PullRequestCreate)

	alertLink = ts.AlertLink{
		ID: alertLink.ID,
	}
	otherAlertAlertLink = ts.AlertLink{
		ID: otherAlertAlertLink.ID,
	}
	otherRefAlertLink = ts.AlertLink{
		ID: otherRefAlertLink.ID,
	}
	otherRepoAlertLink = ts.AlertLink{
		ID: otherRepoAlertLink.ID,
	}

	err = db.Find(&alertLink, "id = ?", alertLink.ID).Error
	require.NoError(t, err)
	err = db.Find(&otherAlertAlertLink, "id = ?", otherAlertAlertLink.ID).Error
	require.NoError(t, err)
	err = db.Find(&otherRefAlertLink, "id = ?", otherRefAlertLink.ID).Error
	require.NoError(t, err)
	err = db.Find(&otherRepoAlertLink, "id = ?", otherRepoAlertLink.ID).Error
	require.NoError(t, err)

	require.Equal(t, pullRequestID, alertLink.PullRequestID)
	require.Empty(t, alertLink.Ref)

	require.Equal(t, pullRequestID, otherAlertAlertLink.PullRequestID)
	require.Empty(t, otherAlertAlertLink.Ref)

	require.Empty(t, otherRefAlertLink.PullRequestID)
	require.NotEmpty(t, otherRefAlertLink.Ref)

	require.Empty(t, otherRepoAlertLink.PullRequestID)
	require.NotEmpty(t, otherRepoAlertLink.Ref)

	requestID := msg.GetRequestContext().GetRequestId()
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

func TestAlertLinkProcessor_PullRequestCreate_NoActor(t *testing.T) {
	db, als, _ := alertLinkProcessorTestSetup(t)

	p := NewAlertLinkProcessor(als)

	msg := createPullRequestCreateTestMessage()
	msg.Actor = nil

	ref := append([]byte("refs/heads/"), msg.PullRequest.HeadBranch...)

	alertLink := ts.AlertLink{
		RepositoryID:   ts.RepositoryEID(msg.Repository.Id),
		LogicalAlertID: ts.LogicalAlertID(123),
		Ref:            ref,
	}
	err := db.Create(&alertLink).Error
	require.NoError(t, err)

	requireProcessEnvelope(t, p, msg, topics.PullRequestCreate)

	alertLink = ts.AlertLink{
		ID: alertLink.ID,
	}

	err = db.Find(&alertLink, "id = ?", alertLink.ID).Error
	require.NoError(t, err)

	require.Equal(t, ts.PullRequestEID(0), alertLink.PullRequestID)
	require.Equal(t, ref, alertLink.Ref)
}

func TestAlertLinkProcessor_PullRequestCreate_Dependabot(t *testing.T) {
	db, als, _ := alertLinkProcessorTestSetup(t)

	p := NewAlertLinkProcessor(als)

	msg := createPullRequestCreateTestMessage()
	msg.Actor.Login = "dependabot[bot]"

	ref := append([]byte("refs/heads/"), msg.PullRequest.HeadBranch...)

	alertLink := ts.AlertLink{
		RepositoryID:   ts.RepositoryEID(msg.Repository.Id),
		LogicalAlertID: ts.LogicalAlertID(123),
		Ref:            ref,
	}
	err := db.Create(&alertLink).Error
	require.NoError(t, err)

	requireProcessEnvelope(t, p, msg, topics.PullRequestCreate)

	alertLink = ts.AlertLink{
		ID: alertLink.ID,
	}

	err = db.Find(&alertLink, "id = ?", alertLink.ID).Error
	require.NoError(t, err)

	require.Equal(t, ts.PullRequestEID(0), alertLink.PullRequestID)
	require.Equal(t, ref, alertLink.Ref)
}

func TestAlertLinkProcessor_PullRequestCreate_Fork(t *testing.T) {
	db, als, _ := alertLinkProcessorTestSetup(t)

	p := NewAlertLinkProcessor(als)

	msg := createPullRequestCreateTestMessage()
	msg.HeadRepository = &entities.Repository{
		Id:            2,
		DefaultBranch: "main",
		ParentId:      msg.Repository.Id,
	}

	ref := append([]byte("refs/heads/"), msg.PullRequest.HeadBranch...)

	alertLink := ts.AlertLink{
		RepositoryID:   ts.RepositoryEID(msg.Repository.Id),
		LogicalAlertID: ts.LogicalAlertID(123),
		Ref:            ref,
	}
	err := db.Create(&alertLink).Error
	require.NoError(t, err)

	requireProcessEnvelope(t, p, msg, topics.PullRequestCreate)

	alertLink = ts.AlertLink{
		ID: alertLink.ID,
	}

	err = db.Find(&alertLink, "id = ?", alertLink.ID).Error
	require.NoError(t, err)

	require.Equal(t, ts.PullRequestEID(0), alertLink.PullRequestID)
	require.Equal(t, ref, alertLink.Ref)
}

func alertLinkProcessorTestSetup(t *testing.T) (*gorm.DB, *alertlinks.Service, *mocks.MockHydroPublisher) {
	t.Helper()

	db := dbtest.RequireConnection(t)
	alertLinkService := alertlink.NewService(db)

	mockCtrl := gomock.NewController(t)
	publisher := mocks.NewMockHydroPublisher(mockCtrl)

	s := alertlinks.NewService(alertLinkService, publisher, elasticsearch.SetUpTestElasticSearchService(t))
	return db, s, publisher
}
