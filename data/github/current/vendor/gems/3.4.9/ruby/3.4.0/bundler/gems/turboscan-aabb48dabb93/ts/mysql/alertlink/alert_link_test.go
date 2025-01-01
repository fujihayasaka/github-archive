package alertlink

import (
	"context"
	"testing"

	"github.com/SamuelTissot/sqltime"
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

func TestDeleteAlertLinks(t *testing.T) {
	db, s, ctx := testSetup(t)

	repoID := ts.RepositoryEID(1234)

	refAlertLinkOne := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlertID,
		Ref:            ref,
	}
	err := db.Create(&refAlertLinkOne).Error
	require.NoError(t, err)

	refAlertLinkTwo := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlertID,
		Ref:            []byte("refs/heads/fix-alert-123"),
	}
	err = db.Create(&refAlertLinkTwo).Error
	require.NoError(t, err)

	refAlertLinkFromOtherRepo := ts.AlertLink{
		RepositoryID:   ts.RepositoryEID(3),
		LogicalAlertID: logicalAlertID,
		Ref:            ref,
	}
	err = db.Create(&refAlertLinkFromOtherRepo).Error
	require.NoError(t, err)

	prAlertLinkOne := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlertID,
		PullRequestID:  pullRequestID,
	}
	err = db.Create(&prAlertLinkOne).Error
	require.NoError(t, err)

	prAlertLinkTwo := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlertID,
		PullRequestID:  ts.PullRequestEID(123),
	}
	err = db.Create(&prAlertLinkTwo).Error
	require.NoError(t, err)

	var alertLinksForRepositoryCount int
	err = db.Model(&ts.AlertLink{}).
		Where("repository_id = ? AND logical_alert_id = ?", repoID, logicalAlertID).
		Count(&alertLinksForRepositoryCount).
		Error
	require.NoError(t, err)
	require.Equal(t, 4, alertLinksForRepositoryCount)

	// Delete ref alert links
	err = s.DeleteAlertLinks(ctx, []ts.AlertLinkID{refAlertLinkOne.ID, refAlertLinkTwo.ID})
	require.NoError(t, err)

	// Count alert links for the repository
	err = db.Model(&ts.AlertLink{}).
		Where("repository_id = ? AND logical_alert_id = ?", repoID, logicalAlertID).
		Count(&alertLinksForRepositoryCount).
		Error
	require.NoError(t, err)
	require.Equal(t, 2, alertLinksForRepositoryCount)

	// Try to find the alert links that should have been deleted
	err = db.
		Where("repository_id = ? AND logical_alert_id = ? AND ref IN (?)", repoID, logicalAlertID, []ts.Ref{ref, []byte("refs/heads/fix-alert-123")}).
		Find(&[]ts.AlertLink{}).
		Error
	require.NoError(t, err)
	require.Empty(t, []ts.AlertLink{})

	// Delete pull request alert links
	err = s.DeleteAlertLinks(ctx, []ts.AlertLinkID{prAlertLinkOne.ID, prAlertLinkTwo.ID})
	require.NoError(t, err)

	// Count alert links for the repository
	err = db.Model(&ts.AlertLink{}).
		Where("repository_id = ? AND logical_alert_id = ?", repoID, logicalAlertID).
		Count(&alertLinksForRepositoryCount).
		Error
	require.NoError(t, err)
	require.Equal(t, 0, alertLinksForRepositoryCount)

	// Try to find the alert links that should have been deleted
	err = db.Where("repository_id = ? AND logical_alert_id = ? AND pull_request_id IN (?)", repoID, logicalAlertID, []ts.PullRequestEID{pullRequestID, ts.PullRequestEID(123)}).Find(&[]ts.AlertLink{}).Error
	require.NoError(t, err)
	require.Empty(t, []ts.AlertLink{})
}

func TestFindAlertLinks(t *testing.T) {
	db, s, ctx := testSetup(t)

	// Populate the database with some alert links
	repoID := ts.RepositoryEID(1234)
	otherRef := []byte("refs/heads/fix-alert-123")
	otherPullRequestID := ts.PullRequestEID(123)

	// Create one logical alert
	now := sqltime.Now()
	rule := &ts.Rule{
		Tool: &ts.Tool{
			CanonicalName: ts.ToolName("tool"),
			GUID:          "tool",
		},
	}
	logicalAlert := ts.LogicalAlert{
		RepositoryID:          repoID,
		Number:                1,
		StableAlertIdentifier: []byte("1"),
		BaseModel:             ts.BaseModel{UpdatedAt: now},
		Rule:                  rule,
	}
	err := db.Create(&logicalAlert).Error
	require.NoError(t, err)

	refAlertLinkOne := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlert.ID,
		Ref:            ref,
	}
	err = db.Create(&refAlertLinkOne).Error
	require.NoError(t, err)

	refAlertLinkTwo := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlert.ID,
		Ref:            otherRef,
	}
	err = db.Create(&refAlertLinkTwo).Error
	require.NoError(t, err)

	refAlertLinkFromOtherRepo := ts.AlertLink{
		RepositoryID:   ts.RepositoryEID(3),
		LogicalAlertID: logicalAlert.ID,
		Ref:            ref,
	}
	err = db.Create(&refAlertLinkFromOtherRepo).Error
	require.NoError(t, err)

	prAlertLinkOne := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlert.ID,
		PullRequestID:  pullRequestID,
	}
	err = db.Create(&prAlertLinkOne).Error
	require.NoError(t, err)

	prAlertLinkTwo := ts.AlertLink{
		RepositoryID:   repoID,
		LogicalAlertID: logicalAlert.ID,
		PullRequestID:  otherPullRequestID,
	}
	err = db.Create(&prAlertLinkTwo).Error
	require.NoError(t, err)

	// Find the ref alert links
	alertLinks, err := s.FindAlertLinks(ctx, []ts.AlertLinkWithoutID{
		{
			RepositoryID: repoID,
			AlertNumber:  logicalAlert.Number,
			Ref:          ref,
		},
		{
			RepositoryID: repoID,
			AlertNumber:  logicalAlert.Number,
			Ref:          otherRef,
		},
	})
	require.NoError(t, err)
	require.Equal(t, 2, len(alertLinks))
	require.ElementsMatch(t, []ts.AlertLinkID{refAlertLinkOne.ID, refAlertLinkTwo.ID}, []ts.AlertLinkID{alertLinks[0].ID, alertLinks[1].ID})

	// Find the PR alert links
	alertLinks, err = s.FindAlertLinks(ctx, []ts.AlertLinkWithoutID{
		{
			RepositoryID:  repoID,
			AlertNumber:   logicalAlert.Number,
			PullRequestID: pullRequestID,
		},
		{
			RepositoryID:  repoID,
			AlertNumber:   logicalAlert.Number,
			PullRequestID: otherPullRequestID,
		},
	})
	require.NoError(t, err)
	require.Equal(t, 2, len(alertLinks))
	require.ElementsMatch(t, []ts.AlertLinkID{prAlertLinkOne.ID, prAlertLinkTwo.ID}, []ts.AlertLinkID{alertLinks[0].ID, alertLinks[1].ID})
}

func testSetup(t *testing.T) (*gorm.DB, *Service, context.Context) {
	t.Helper()

	db := dbtest.RequireConnection(t)
	s := NewService(db)
	ctx := context.Background()
	return db, s, ctx
}
