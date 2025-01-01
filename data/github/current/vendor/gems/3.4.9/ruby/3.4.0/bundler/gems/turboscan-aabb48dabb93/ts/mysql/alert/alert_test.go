package alert

import (
	"context"
	"encoding/binary"
	"fmt"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
)

var stableIDcounter = 0

func newStableID() []byte {
	stableIDcounter++
	stableID := make([]byte, 8)
	binary.BigEndian.PutUint64(stableID, uint64(stableIDcounter))
	return stableID
}

func newCodeFlow(i uint32) ts.CodeFlow {
	message := fmt.Sprintf("some message (%d)", i)
	return ts.CodeFlow{
		FilePath: "/some/path",
		Region: ts.Region{
			StartLine:   1 + i,
			EndLine:     100,
			StartColumn: 4 + i,
			EndColumn:   10,
		},
		Message:         &message,
		CodeFlowIndex:   i,
		ThreadFlowIndex: i,
		StepIndex:       i,
	}
}

func newPhysicalAlert() ts.PhysicalAlert {
	now := sqltime.Now()
	return ts.PhysicalAlert{
		RepositoryID: ts.RepositoryEID(1),
		Analysis: &ts.Analysis{
			RepositoryID:       ts.RepositoryEID(1),
			SourceRepositoryID: ts.RepositoryEID(1),
			ConfigurationID:    1,
			CommitOid:          "xxx",
			Ref:                []byte("refs/heads/ref1"),
		},
		StableAlertIdentifier: newStableID(),
		LastStateChangeAt:     now,
	}
}

func newRelatedLocation() *ts.RelatedLocation {
	return &ts.RelatedLocation{
		RepositoryID: 1,
		FilePath:     "/other/file.js",
		Region: ts.Region{
			StartLine:   uint32(29),
			EndLine:     uint32(44),
			StartColumn: uint32(8),
			EndColumn:   uint32(9),
		},
		Message:          "an important location",
		ReplacementIndex: uint32(2),
		PhysicalAlertID:  ts.PhysicalAlertID(1234),
	}
}

func Test_bulkWritePhysicalAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	as := TestService(db)

	alerts := make([]*ts.PhysicalAlert, 3)
	for i := range alerts {
		pa := newPhysicalAlert()
		pa.RelatedLocations = []*ts.RelatedLocation{
			newRelatedLocation(),
			newRelatedLocation(),
			newRelatedLocation(),
		}
		pa.CodeFlowsDocument = &ts.CodeFlowsDocument{
			RepositoryID: 1,
			Document: ts.CodeFlows{
				newCodeFlow(0),
				newCodeFlow(0),
			},
		}
		alerts[i] = &pa
	}

	// chunkSize is two to make sure we have to use both complete and
	// partial chunks
	err := as.writePhysicalAlerts(ctx, alerts, 2, 1)
	require.NoError(t, err)

	var actualAlerts []ts.PhysicalAlert
	err = db.Find(&actualAlerts).Error
	require.NoError(t, err)
	require.Len(t, actualAlerts, 3)

	// Check that the related locations were no longer stored
	for _, p := range actualAlerts {
		require.NotZero(t, p.ID)

		var actualLocations []ts.RelatedLocation
		err := db.Where("physical_alert_id = ?", p.ID).Find(&actualLocations).Error
		require.NoError(t, err)
		require.Len(t, actualLocations, 0)
	}
}
func Test_SkipCodeFlows(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	as := TestService(db)

	alerts := make([]*ts.PhysicalAlert, 6)
	for i := range alerts {
		pa := newPhysicalAlert()
		pa.CodeFlowsDocument = &ts.CodeFlowsDocument{
			RepositoryID: 1,
			Document: ts.CodeFlows{
				newCodeFlow(uint32(i % 3)),
				newCodeFlow(uint32(i%3) + 1),
			},
		}
		alerts[i] = &pa
	}

	err := as.writePhysicalAlerts(ctx, alerts, 2, 1)
	require.NoError(t, err)
	dbtest.RequireCount(t, 0, db.Model(ts.CodeFlowsDocument{}))

	var actualAlerts []*ts.PhysicalAlert
	err = db.Find(&actualAlerts).Error
	require.NoError(t, err)
	require.Len(t, actualAlerts, 6)

	for _, alert := range actualAlerts {
		require.Zero(t, alert.CodeFlowsDocumentID)
	}
}

func TestFilterPreload(t *testing.T) {
	v, found := filterPreload([]string{"PhysicalAlerts.Test"}, "PhysicalAlerts")
	require.Equal(t, []string{"PhysicalAlerts.Test"}, v)
	require.True(t, found)
	v, found = filterPreload([]string{"PhysicalAlerts", "PhysicalAlerts", "PhysicalAlerts.Test"}, "PhysicalAlerts")
	require.Equal(t, []string{"PhysicalAlerts.Test"}, v)
	require.True(t, found)
	v, found = filterPreload([]string{"Analysis"}, "PhysicalAlerts")
	require.Equal(t, []string{"Analysis"}, v)
	require.False(t, found)
}

func TestPhysicalAlertByIDs(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	as := TestService(db)

	pa := newPhysicalAlert()
	require.NoError(t, db.Create(&pa).Error)

	actual, err := as.PhysicalAlertByIDs(ctx, ts.RepositoryEID(1), []ts.PhysicalAlertID{pa.ID}, nil)
	require.NoError(t, err)
	require.Len(t, actual, 1)
	require.Equal(t, pa.ID, actual[0].ID)
}

func Test_IsCanonicalAlertUpdate(t *testing.T) {
	defaultRef := []byte("refs/heads/main")
	otherRef := []byte("refs/heads/other")
	yetAnotherRef := []byte("refs/heads/yet-another")

	defaultConfiguration := &ts.Configuration{
		ID:  1,
		Ref: defaultRef,
	}

	otherConfiguration := &ts.Configuration{
		ID:  2,
		Ref: otherRef,
	}

	yetAnotherConfiguration := &ts.Configuration{
		ID:  3,
		Ref: yetAnotherRef,
	}

	repo := &ts.Repository{
		DefaultRef: defaultRef,
	}

	analysis := &ts.Analysis{
		Ref:           otherRef,
		Configuration: otherConfiguration,
	}
	la := &ts.LogicalAlert{}

	// will update from non-default ref initially when there is no default configuration
	require.True(t, IsCanonicalAlertUpdate(analysis, repo, la))

	analysis = &ts.Analysis{
		Ref:           yetAnotherRef,
		Configuration: yetAnotherConfiguration,
	}

	la = &ts.LogicalAlert{
		// logical alert configuration set from previous update
		DefaultConfigurationID: otherConfiguration.ID,
		DefaultConfiguration:   otherConfiguration,
	}

	// will update again from the most recent ref while there is no default ref instance information
	require.True(t, IsCanonicalAlertUpdate(analysis, repo, la))

	analysis = &ts.Analysis{
		Ref:           defaultRef,
		Configuration: defaultConfiguration,
	}

	la = &ts.LogicalAlert{
		// logical alert default configuration set from previous update
		DefaultConfigurationID: yetAnotherConfiguration.ID,
		DefaultConfiguration:   yetAnotherConfiguration,
	}
	// will update from the default ref
	require.True(t, IsCanonicalAlertUpdate(analysis, repo, la))

	la = &ts.LogicalAlert{
		// logical alert default configuration set from previous update
		DefaultConfigurationID: defaultConfiguration.ID,
		DefaultConfiguration:   defaultConfiguration,
	}

	// will always update from the default ref (to get most up-to-date instance information)
	require.True(t, IsCanonicalAlertUpdate(analysis, repo, la))

	analysis = &ts.Analysis{
		Ref:           otherRef,
		Configuration: otherConfiguration,
	}

	la = &ts.LogicalAlert{
		// logical alert default configuration set from previous update
		DefaultConfigurationID: defaultConfiguration.ID,
		DefaultConfiguration:   defaultConfiguration,
	}

	// will not update from a non-default ref when there is default ref instance information
	require.False(t, IsCanonicalAlertUpdate(analysis, repo, la))
}

func TestSecurityCampaignAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	as := TestService(db)

	la1 := &ts.LogicalAlert{
		ID:                    ts.LogicalAlertID(19),
		Number:                uint32(1),
		RepositoryID:          ts.RepositoryEID(1),
		StableAlertIdentifier: []byte{105},
	}
	la2 := &ts.LogicalAlert{
		ID:                    ts.LogicalAlertID(20),
		Number:                uint32(2),
		RepositoryID:          ts.RepositoryEID(1),
		StableAlertIdentifier: []byte{106},
	}
	la3 := &ts.LogicalAlert{
		ID:                    ts.LogicalAlertID(21),
		Number:                uint32(1),
		RepositoryID:          ts.RepositoryEID(2),
		StableAlertIdentifier: []byte{107},
	}
	la4 := &ts.LogicalAlert{
		ID:                    ts.LogicalAlertID(22),
		Number:                uint32(2),
		RepositoryID:          ts.RepositoryEID(2),
		StableAlertIdentifier: []byte{108},
	}
	dbtest.RequireCreate(t, db, &la1)
	dbtest.RequireCreate(t, db, &la2)
	dbtest.RequireCreate(t, db, &la3)
	dbtest.RequireCreate(t, db, &la4)

	repoNumbers := []ts.RepoNumber{
		{RepositoryID: ts.RepositoryEID(1), Number: 1},
		{RepositoryID: ts.RepositoryEID(1), Number: 2},
		{RepositoryID: ts.RepositoryEID(2), Number: 1},
	}
	securityCampaignID := ts.SecurityCampaignEID(1)

	_, err := as.WriteSecurityCampaignAlerts(ctx, repoNumbers, securityCampaignID)
	require.NoError(t, err)

	securityCampaignAlerts := []ts.SecurityCampaignAlert{}
	// Select specific columns to avoid comparing time stamps
	err = db.Where("security_campaign_id = ?", securityCampaignID).
		Select("security_campaign_id, repository_id, logical_alert_id").
		Find(&securityCampaignAlerts).Error

	require.NoError(t, err)
	require.Len(t, securityCampaignAlerts, 3)

	expectedSecurityCampaignAlerts := []ts.SecurityCampaignAlert{
		{
			SecurityCampaignID: securityCampaignID,
			RepositoryID:       ts.RepositoryEID(1),
			LogicalAlertID:     la1.ID,
		},
		{
			SecurityCampaignID: securityCampaignID,
			RepositoryID:       ts.RepositoryEID(1),
			LogicalAlertID:     la2.ID,
		},
		{
			SecurityCampaignID: securityCampaignID,
			RepositoryID:       ts.RepositoryEID(2),
			LogicalAlertID:     la3.ID,
		},
	}
	require.ElementsMatch(t, expectedSecurityCampaignAlerts, securityCampaignAlerts)

	// Writing the same alerts again, which should not create duplicates
	_, err = as.WriteSecurityCampaignAlerts(ctx, repoNumbers, securityCampaignID)
	require.NoError(t, err)
	securityCampaignAlerts = []ts.SecurityCampaignAlert{}
	err = db.Where("security_campaign_id = ?", securityCampaignID).
		Select("security_campaign_id, repository_id, logical_alert_id").
		Find(&securityCampaignAlerts).Error
	require.NoError(t, err)
	require.Len(t, securityCampaignAlerts, 3)

	// Creating a new campaign
	securityCampaignID2 := ts.SecurityCampaignEID(2)
	_, err = as.WriteSecurityCampaignAlerts(ctx, repoNumbers, securityCampaignID2)
	require.NoError(t, err)

	// Deleting the alerts for the first campaign should remove them from the table
	// but leave the new campaign in place.
	_, err = as.DeleteSecurityCampaignAlerts(ctx, securityCampaignID)
	require.NoError(t, err)
	securityCampaignAlerts = []ts.SecurityCampaignAlert{}
	err = db.Select("security_campaign_id, repository_id, logical_alert_id").
		Find(&securityCampaignAlerts).Error
	require.NoError(t, err)

	expectedSecurityCampaignAlerts2 := []ts.SecurityCampaignAlert{
		{
			SecurityCampaignID: securityCampaignID2,
			RepositoryID:       ts.RepositoryEID(1),
			LogicalAlertID:     la1.ID,
		},
		{
			SecurityCampaignID: securityCampaignID2,
			RepositoryID:       ts.RepositoryEID(1),
			LogicalAlertID:     la2.ID,
		},
		{
			SecurityCampaignID: securityCampaignID2,
			RepositoryID:       ts.RepositoryEID(2),
			LogicalAlertID:     la3.ID,
		},
	}
	require.ElementsMatch(t, expectedSecurityCampaignAlerts2, securityCampaignAlerts)
}
