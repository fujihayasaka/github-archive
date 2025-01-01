package twirp

import (
	"context"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	tshydro_entities "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0/entities"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/enabled_status"
	"github.com/github/turboscan/ts/mocks"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/proto"
)

// Most tests of this endpoint are cassette tests -- see
// ts/cassettes/sessions/enabled_test.go. Things tested
// here are more internal to the endpoint.

func setup(t *testing.T) (
	*gorm.DB,
	context.Context,
	*mocks.HydroEnabledStatusPublisher,
	*ResultsResolver,
) {
	t.Helper()
	db := dbtest.RequireConnectionWithoutAutoIncrement(t)
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	mockPub := mocks.NewHydroEnabledStatusPublisher(mockCtrl)
	rs := repository.NewService(db)
	e := newEnabledStatusService(t, db, rs, mockPub, true)
	resolver := NewResultsResolver(nil, nil, nil, nil, nil, nil, rs, nil, nil, nil, nil, nil, nil, nil, nil, nil, e, false)

	return db, ctx, mockPub, resolver
}

func newEnabledStatusService(t *testing.T, db *gorm.DB, rs *repository.Service, publisher enabled_status.Publisher, shouldPublish bool) *enabled_status.EnabledStatusService {
	t.Helper()

	alertService := alert.TestService(db)
	mockCtrl := gomock.NewController(t)
	codeQLRunPublisher := mocks.NewMockCodeqlRunPublisher(mockCtrl)
	managedAnalysisService := managedanalysis.NewService(db, codeQLRunPublisher)

	return enabled_status.NewEnabledStatusService(db, alertService, rs, managedAnalysisService, publisher, shouldPublish)
}

func TestGetCodeScanningEnabledPublishesToHydro(t *testing.T) {
	db, ctx, mockPub, resolver := setup(t)
	repoID := uint64(1)
	defaultRef := []byte("refs/heads/main")

	repo := &ts.Repository{
		RepositoryID: ts.RepositoryEID(repoID), OwnerID: 1,
		SourceUpdatedAt: sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC),
		DefaultRef:      defaultRef,
	}
	dbtest.RequireCreate(t, db, repo)

	req := &proto.GetCodeScanningEnabledRequest{
		RepositoryId:        repoID,
		DefaultRefNameBytes: defaultRef,
	}

	// No published state in the DB yet
	dbtest.RequireCount(t, 0, db.Model(&ts.PublishedEnabledState{}))

	// statusService.PublishStatusIfChanged is called by GetCodeScanningEnabled;
	// that'll not publish in this case as nothing has been published before and there is no analysis.

	_, err := resolver.GetCodeScanningEnabled(ctx, req)
	require.NoError(t, err)

	// We can see in the db that nothing was actually published
	dbtest.RequireCount(t, 0, db.Model(&ts.PublishedEnabledState{}))

	// We add an analysis for anything but the default branch
	// It should still be disabled but we'll actually publish.
	CodeQL := &ts.Tool{ID: 1, CanonicalName: "CodeQL"}
	dbtest.RequireCreate(t, db, CodeQL)
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:       ts.RepositoryEID(repoID),
		SourceRepositoryID: 1,
		Ref:                []byte("refs/pulls/1"),
		MostRecent:         true,
		AnalysisComplete:   true,
		Tool:               CodeQL,
	})

	mockPub.EXPECT().EnablementEvent(gomock.Any(), &tshydro.EnablementEvent{
		RepositoryId: int64(1),
		Enabled:      false,
		Reason:       tshydro_entities.EnablementReason_ENABLEMENT_REASON_OBSERVED_CHANGE,
	}).Return(nil).Times(1)

	_, err = resolver.GetCodeScanningEnabled(ctx, req)
	require.NoError(t, err)

	// We'll also see details of the data in the database
	dbtest.RequireCount(t, 1, db.Model(&ts.PublishedEnabledState{}))
	var publishedState ts.PublishedEnabledState
	err = db.Where("repository_id = ?", repoID).First(&publishedState).Error
	require.NoError(t, err)
	require.Equal(t, ts.EnablementReason_OBSERVED_CHANGE, publishedState.Reason)
	require.Equal(t, false, publishedState.Enabled)

	// We shouldn't see another EnablementEvent when we call again,
	// as nothing has changed (hence `Times(1)` above).

	_, err = resolver.GetCodeScanningEnabled(ctx, req)
	require.NoError(t, err)

	// Add an analysis so that Code Scanning is considered enabled,
	// and we should then see another EnablementEvent when GetCodeScanningEnabled
	// is called.

	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:       ts.RepositoryEID(repoID),
		SourceRepositoryID: 1,
		Ref:                defaultRef,
		MostRecent:         true,
		AnalysisComplete:   true,
		Tool:               CodeQL,
	})

	mockPub.EXPECT().EnablementEvent(gomock.Any(), &tshydro.EnablementEvent{
		RepositoryId: int64(1),
		Enabled:      true,
		Reason:       tshydro_entities.EnablementReason_ENABLEMENT_REASON_OBSERVED_CHANGE,
	}).Return(nil).Times(1)

	_, err = resolver.GetCodeScanningEnabled(ctx, req)
	require.NoError(t, err)
}
