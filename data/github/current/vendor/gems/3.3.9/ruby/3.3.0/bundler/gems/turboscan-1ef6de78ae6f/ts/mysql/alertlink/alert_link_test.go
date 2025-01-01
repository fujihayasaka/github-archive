package alertlink

import (
	"context"
	"testing"

	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
)

const (
	repoID         = ts.RepositoryEID(1)
	logicalAlertID = ts.LogicalAlertID(123)
	pullRequestID  = ts.PullRequestEID(789)
)

var (
	ref = []byte("refs/heads/campaign-fix-1-2")
)

func TestCountAlertLinkByRef(t *testing.T) {
	db, s, ctx := testSetup(t)

	alertLink := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlertID,
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

	otherRepoAlertLink := ts.AlertLink{
		RepositoryID:   ts.RepositoryEID(78923),
		LogicalAlertID: ts.LogicalAlertID(1235),
		Ref:            ref,
	}
	err = db.Create(&otherRepoAlertLink).Error
	require.NoError(t, err)

	otherRefAlertLink := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlertID,
		Ref:            []byte("refs/heads/campaign-fix-1-3"),
	}
	err = db.Create(&otherRefAlertLink).Error
	require.NoError(t, err)

	prAlertLink := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlertID,
		PullRequestID:  pullRequestID,
	}
	err = db.Create(&prAlertLink).Error
	require.NoError(t, err)

	count, err := s.CountAlertLinkByRef(ctx, repoID, ref)
	require.NoError(t, err)
	require.Equal(t, uint64(2), count)
}

func TestUpdatePRFromRef(t *testing.T) {
	db, s, ctx := testSetup(t)

	alertLink := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlertID,
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

	otherRepoAlertLink := ts.AlertLink{
		RepositoryID:   ts.RepositoryEID(78923),
		LogicalAlertID: ts.LogicalAlertID(1235),
		Ref:            ref,
	}
	err = db.Create(&otherRepoAlertLink).Error
	require.NoError(t, err)

	otherRefAlertLink := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlertID,
		Ref:            []byte("refs/heads/campaign-fix-1-3"),
	}
	err = db.Create(&otherRefAlertLink).Error
	require.NoError(t, err)

	prAlertLink := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlertID,
		PullRequestID:  pullRequestID,
	}
	err = db.Create(&prAlertLink).Error
	require.NoError(t, err)

	updatedLinks, err := s.UpdatePRFromRef(ctx, repoID, ref, ts.PullRequestEID(789023))
	require.NoError(t, err)

	require.Equal(t, 2, len(updatedLinks))
	require.ElementsMatch(t, []ts.AlertLinkID{alertLink.ID, otherAlertAlertLink.ID}, []ts.AlertLinkID{updatedLinks[0].ID, updatedLinks[1].ID})
	require.Equal(t, ts.PullRequestEID(789023), updatedLinks[0].PullRequestID)
	require.Nil(t, updatedLinks[0].Ref)
	require.Equal(t, ts.PullRequestEID(789023), updatedLinks[1].PullRequestID)
	require.Nil(t, updatedLinks[1].Ref)

	alertLink = ts.AlertLink{
		ID: alertLink.ID,
	}
	otherAlertAlertLink = ts.AlertLink{
		ID: otherAlertAlertLink.ID,
	}
	otherRepoAlertLink = ts.AlertLink{
		ID: otherRepoAlertLink.ID,
	}
	otherRefAlertLink = ts.AlertLink{
		ID: otherRefAlertLink.ID,
	}
	prAlertLink = ts.AlertLink{
		ID: prAlertLink.ID,
	}

	err = db.Find(&alertLink, "id = ?", alertLink.ID).Error
	require.NoError(t, err)
	err = db.Find(&otherAlertAlertLink, "id = ?", otherAlertAlertLink.ID).Error
	require.NoError(t, err)
	err = db.Find(&otherRepoAlertLink, "id = ?", otherRepoAlertLink.ID).Error
	require.NoError(t, err)
	err = db.Find(&otherRefAlertLink, "id = ?", otherRefAlertLink.ID).Error
	require.NoError(t, err)
	err = db.Find(&prAlertLink, "id = ?", prAlertLink.ID).Error
	require.NoError(t, err)

	require.Equal(t, ts.PullRequestEID(789023), alertLink.PullRequestID)
	require.Empty(t, alertLink.Ref)

	require.Equal(t, ts.PullRequestEID(789023), otherAlertAlertLink.PullRequestID)
	require.Empty(t, otherAlertAlertLink.Ref)

	require.Empty(t, otherRepoAlertLink.PullRequestID)
	require.NotEmpty(t, otherRepoAlertLink.Ref)

	require.Empty(t, otherRefAlertLink.PullRequestID)
	require.NotEmpty(t, otherRefAlertLink.Ref)

	require.Equal(t, pullRequestID, prAlertLink.PullRequestID)
	require.Empty(t, prAlertLink.Ref)
}

func testSetup(t *testing.T) (*gorm.DB, *Service, context.Context) {
	t.Helper()

	db := dbtest.RequireConnection(t)
	s := NewService(db)
	ctx := context.Background()
	return db, s, ctx
}
