package consumers

import (
	"context"
	"testing"
	"time"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	tshydro_entities "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0/entities"
	"github.com/github/turboscan/ts/enabled_status"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/jinzhu/gorm"

	"github.com/SamuelTissot/sqltime"
	"go.uber.org/mock/gomock"
	timestamppb "google.golang.org/protobuf/types/known/timestamppb"

	security_center "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v1"
	v1_entities "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v1/entities"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/mocks"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/stretchr/testify/require"
)

func setup(t *testing.T) (
	*gorm.DB,
	context.Context,
	*mocks.MockIndexer,
	*mocks.HydroEnabledStatusPublisher,
	*repository.Service,
	*RepoEventProcessor,
) {
	t.Helper()
	db := dbtest.RequireConnectionWithoutAutoIncrement(t)
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	indexer := mocks.NewMockIndexer(mockCtrl)
	mockPub := mocks.NewHydroEnabledStatusPublisher(mockCtrl)
	mockCodeQLRunPub := mocks.NewMockCodeqlRunPublisher(mockCtrl)
	rs := repository.NewService(db)
	e := newEnabledStatusService(db, rs, mockPub, mockCodeQLRunPub, true)
	consumer := NewRepoEventProcessor(rs, e, alert.TestService(db), indexer)

	return db, ctx, indexer, mockPub, rs, consumer
}

func TestRepoEventProcessorCreate(t *testing.T) {
	db, ctx, _, mockPub, rs, consumer := setup(t)

	defaultRef := []byte("refs/heads/master")
	msg := &security_center.SecurityFeatureRepoUpdate{
		Repository: &v1_entities.Repository{
			Id:               1,
			OrganizationId:   wrapperspb.Int64(2),
			DefaultBranchRef: defaultRef,
		},
		SecurityFeatureDetails: []*security_center.SecurityFeatureRepoUpdate_SecurityFeatureDetail{
			{
				SecurityFeature: v1_entities.SecurityFeature_CODE_SCANNING,
				FeatureVisible:  true,
			},
		},
	}
	now := timestamppb.Now()
	// TODO: here we index docouments, but that doesnt trigger because there are no alerts.

	// Create an analysis for this repo, which means that repo event processor
	// will trigger the update code (including publishing) instead of returning early.
	// The analysis is on the default branch, so Code Scanning should be considered enabled.
	a1 := &ts.Analysis{ID: 1, RepositoryID: 1, SourceRepositoryID: 1, Ref: defaultRef}
	dbtest.RequireCreate(t, db, a1)

	// The "default branch change" logic catches the case where the repo wasn't
	// in the repositories table, so it will publish an event here.
	mockPub.EXPECT().EnablementEvent(gomock.Any(), &tshydro.EnablementEvent{
		RepositoryId: int64(1),
		Enabled:      false,
		Reason:       tshydro_entities.EnablementReason_ENABLEMENT_REASON_DEFAULT_BRANCH_CHANGE,
	}).Return(nil)

	err := consumer.RepoUpdate(ctx, msg, now)
	require.NoError(t, err)

	result, err := rs.Find(ctx, 1)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, ts.RepositoryEID(1), result.RepositoryID)
	require.Equal(t, ts.OwnerEID(2), result.OwnerID)
	require.Equal(t, defaultRef, result.DefaultRef)
	require.True(t, result.CodeScanningEnabled)
}

func TestRepoEventProcessorPublishesToHydroForNewRepoIfAnalysisExistsEvenIfCodeScanningIsDisabled(t *testing.T) {
	db, ctx, _, mockPub, rs, consumer := setup(t)

	defaultRef := []byte("refs/heads/master")
	msg := &security_center.SecurityFeatureRepoUpdate{
		Repository: &v1_entities.Repository{
			Id:               1,
			OrganizationId:   wrapperspb.Int64(2),
			DefaultBranchRef: defaultRef,
		},
		SecurityFeatureDetails: []*security_center.SecurityFeatureRepoUpdate_SecurityFeatureDetail{
			{
				SecurityFeature: v1_entities.SecurityFeature_CODE_SCANNING,
				FeatureVisible:  false,
			},
		},
	}
	now := timestamppb.Now()
	// TODO: here we index docouments, but that doesnt trigger because there are no alerts.

	// Create an analysis for this repo, which means that repo event processor
	// will trigger the update code (including publishing) instead of returning early.
	// The publishing should happen even though the analysis is not on the default branch.
	a1 := &ts.Analysis{ID: 1, RepositoryID: 1, SourceRepositoryID: 1, Ref: []byte("refs/heads/other")}
	dbtest.RequireCreate(t, db, a1)

	// Since this is a previously unknown repo, we should publish an event
	// despite `FeatureVisible: false`.
	mockPub.EXPECT().EnablementEvent(gomock.Any(), &tshydro.EnablementEvent{
		RepositoryId: int64(1),
		Enabled:      false,
		Reason:       tshydro_entities.EnablementReason_ENABLEMENT_REASON_DEFAULT_BRANCH_CHANGE,
	}).Return(nil)

	err := consumer.RepoUpdate(ctx, msg, now)
	require.NoError(t, err)

	result, err := rs.Find(ctx, 1)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, ts.RepositoryEID(1), result.RepositoryID)
	require.Equal(t, ts.OwnerEID(2), result.OwnerID)
	require.Equal(t, defaultRef, result.DefaultRef)
	require.False(t, result.CodeScanningEnabled)
}

func TestRepoEventProcessorDefaultRefUpdate(t *testing.T) {
	db, ctx, _, mockPub, rs, consumer := setup(t)

	dbtest.RequireCreate(t, db, &ts.Repository{
		RepositoryID:        1,
		OwnerID:             2,
		SourceUpdatedAt:     sqltime.Now(),
		CodeScanningEnabled: true,
		DefaultRef:          []byte("refs/heads/master"),
	})

	msg := defaultRefUpdateMessage()
	now := timestamppb.Now()
	repo, err := RepositoryFromProto(msg, now)
	require.NoError(t, err)
	// TODO: here we index docouments, but that doesnt trigger because there are no alerts.

	// Create an analysis so the status publisher will decide to emit an event to Hydro
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:       repo.RepositoryID,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
	})

	// Since we've never published disablement, this will trigger a publish
	// even though nothing has actually changed in that regard.
	mockPub.EXPECT().EnablementEvent(gomock.Any(), &tshydro.EnablementEvent{
		RepositoryId: int64(1),
		Enabled:      false,
		Reason:       tshydro_entities.EnablementReason_ENABLEMENT_REASON_DEFAULT_BRANCH_CHANGE,
	}).Return(nil)

	err = consumer.RepoUpdate(ctx, msg, now)
	require.NoError(t, err)

	result, err := rs.Find(ctx, 1)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, ts.RepositoryEID(1), result.RepositoryID)
	require.Equal(t, ts.OwnerEID(22), result.OwnerID)
	require.False(t, result.CodeScanningEnabled)
	require.Equal(t, []byte("refs/heads/main"), result.DefaultRef)
}

func TestRepoEventProcessorDefaultRefUpdateEnablingCodeScanning(t *testing.T) {
	// In this test, we have an analysis for "main", but not for "master".
	// At the beginning of the test, the default branch is "master",
	// so code scanning is considered disabled.
	//
	// When the repo event processor receives an update that changes the
	// default branch to "main", it should notice that this constitutes
	// enabling code scanning, and should publish to Hydro accordingly.

	db, ctx, _, mockPub, rs, consumer := setup(t)

	dbtest.RequireCreate(t, db, &ts.Repository{
		RepositoryID:        1,
		OwnerID:             2,
		SourceUpdatedAt:     sqltime.Now(),
		CodeScanningEnabled: true,
		DefaultRef:          []byte("refs/heads/master"),
	})

	CodeQL := &ts.Tool{ID: 1, CanonicalName: "CodeQL"}
	dbtest.RequireCreate(t, db, CodeQL)
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
		MostRecent:         true,
		AnalysisComplete:   true,
		Tool:               CodeQL,
	})

	msg := defaultRefUpdateMessage()
	now := timestamppb.Now()
	// TODO: here we index docouments, but that doesnt trigger because there are no alerts.

	mockPub.EXPECT().EnablementEvent(gomock.Any(), &tshydro.EnablementEvent{
		RepositoryId: int64(1),
		Enabled:      true,
		Reason:       tshydro_entities.EnablementReason_ENABLEMENT_REASON_DEFAULT_BRANCH_CHANGE,
	}).Return(nil)

	err := consumer.RepoUpdate(ctx, msg, now)
	require.NoError(t, err)

	result, err := rs.Find(ctx, 1)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, ts.RepositoryEID(1), result.RepositoryID)
	require.Equal(t, ts.OwnerEID(22), result.OwnerID)
	require.False(t, result.CodeScanningEnabled)
	require.Equal(t, []byte("refs/heads/main"), result.DefaultRef)
}

func TestRepoEventProcessorDefaultRefUpdateDisablingCodeScanning(t *testing.T) {
	// In this test, we have an analysis for "master", but not for "main".
	// At the beginning of the test, the default branch is "master",
	// so code scanning is considered enabled.
	//
	// When the repo event processor receives an update that changes the
	// default branch to "main", it should notice that this constitutes
	// disabling code scanning, and should publish to Hydro accordingly.

	db, ctx, _, mockPub, rs, consumer := setup(t)

	dbtest.RequireCreate(t, db, &ts.Repository{
		RepositoryID:        1,
		OwnerID:             2,
		SourceUpdatedAt:     sqltime.Now(),
		CodeScanningEnabled: true,
		DefaultRef:          []byte("refs/heads/master"),
	})

	CodeQL := &ts.Tool{ID: 1, CanonicalName: "CodeQL"}
	dbtest.RequireCreate(t, db, CodeQL)
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/master"),
		MostRecent:         true,
		AnalysisComplete:   true,
		Tool:               CodeQL,
	})

	msg := defaultRefUpdateMessage()
	now := timestamppb.Now()
	// TODO: here we index docouments, but that doesnt trigger because there are no alerts.

	mockPub.EXPECT().EnablementEvent(gomock.Any(), &tshydro.EnablementEvent{
		RepositoryId: int64(1),
		Enabled:      false,
		Reason:       tshydro_entities.EnablementReason_ENABLEMENT_REASON_DEFAULT_BRANCH_CHANGE,
	}).Return(nil)

	err := consumer.RepoUpdate(ctx, msg, now)
	require.NoError(t, err)

	result, err := rs.Find(ctx, 1)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, ts.RepositoryEID(1), result.RepositoryID)
	require.Equal(t, ts.OwnerEID(22), result.OwnerID)
	require.False(t, result.CodeScanningEnabled)
	require.Equal(t, []byte("refs/heads/main"), result.DefaultRef)
}

func newEnabledStatusService(db *gorm.DB, rs *repository.Service, publisher enabled_status.Publisher, runPublisher managedanalysis.CodeqlRunPublisher, shouldPublish bool) *enabled_status.EnabledStatusService {
	alertService := alert.TestService(db)
	managedAnalysisService := managedanalysis.NewService(db, runPublisher)

	return enabled_status.NewEnabledStatusService(db, alertService, rs, managedAnalysisService, publisher, shouldPublish)
}

// returns a message which updates the default branch ref to "/refs/heads/main"
func defaultRefUpdateMessage() *security_center.SecurityFeatureRepoUpdate {
	return &security_center.SecurityFeatureRepoUpdate{
		Repository: &v1_entities.Repository{
			Id:               1,
			OrganizationId:   wrapperspb.Int64(22),
			DefaultBranchRef: []byte("refs/heads/main"),
		},
		SecurityFeatureDetails: []*security_center.SecurityFeatureRepoUpdate_SecurityFeatureDetail{
			{
				SecurityFeature: v1_entities.SecurityFeature_CODE_SCANNING,
				FeatureVisible:  false,
			},
			{
				SecurityFeature: v1_entities.SecurityFeature_SECRET_SCANNING,
				FeatureVisible:  true,
			},
		},
	}
}

func TestRepoEventProcessorMetadataUpdate(t *testing.T) {
	db, ctx, indexer, _, rs, consumer := setup(t)

	dbtest.RequireCreate(t, db, &ts.Repository{
		RepositoryID:        1,
		OwnerID:             2,
		SourceUpdatedAt:     sqltime.Now(),
		CodeScanningEnabled: true,
		DefaultRef:          []byte("refs/heads/main"),
	})

	msg := defaultRefUpdateMessage()
	indexer.EXPECT().UpdateRepositoryMetadata(gomock.Any(), gomock.Any()).Times(1)

	err := consumer.RepoUpdate(ctx, msg, timestamppb.Now())
	require.NoError(t, err)

	result, err := rs.Find(ctx, 1)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, ts.RepositoryEID(1), result.RepositoryID)
	require.Equal(t, ts.OwnerEID(22), result.OwnerID)
	require.False(t, result.CodeScanningEnabled)
	require.Equal(t, []byte("refs/heads/main"), result.DefaultRef)
}

func TestRepoEventProcessorUpdateOnTransfer(t *testing.T) {
	db, ctx, indexer, _, rs, consumer := setup(t)

	dbtest.RequireCreate(t, db, &ts.Repository{
		RepositoryID:    1,
		OwnerID:         2,
		SourceUpdatedAt: sqltime.Now(),
		DefaultRef:      []byte("refs/heads/master"),
	})
	msg := &security_center.SecurityFeatureRepoUpdate{
		Repository: &v1_entities.Repository{
			Id:               1,
			OrganizationId:   wrapperspb.Int64(0),
			DefaultBranchRef: []byte("refs/heads/master"),
		},
		SecurityFeatureDetails: []*security_center.SecurityFeatureRepoUpdate_SecurityFeatureDetail{
			{
				SecurityFeature: v1_entities.SecurityFeature_CODE_SCANNING,
				FeatureVisible:  true,
			},
		},
	}
	indexer.EXPECT().UpdateRepositoryMetadata(gomock.Any(), gomock.Any()).Times(1)

	err := consumer.RepoUpdate(ctx, msg, timestamppb.Now())
	require.NoError(t, err)

	result, err := rs.Find(ctx, 1)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, ts.OwnerEID(0), result.OwnerID)
}

func TestRepoEventProcessorNoop(t *testing.T) {
	db, ctx, _, _, rs, consumer := setup(t)
	expectedRepoID := ts.RepositoryEID(1)

	// No record should be added if CodeScanningEnabled is false
	msg := &security_center.SecurityFeatureRepoUpdate{
		Repository: &v1_entities.Repository{
			Id:               int64(expectedRepoID),
			OrganizationId:   wrapperspb.Int64(2),
			DefaultBranchRef: []byte("refs/heads/master"),
		},
		SecurityFeatureDetails: []*security_center.SecurityFeatureRepoUpdate_SecurityFeatureDetail{
			{
				SecurityFeature: v1_entities.SecurityFeature_CODE_SCANNING,
				FeatureVisible:  false,
			},
		},
	}
	err := consumer.RepoUpdate(ctx, msg, timestamppb.Now())
	require.NoError(t, err)
	result, err := rs.Find(ctx, expectedRepoID)
	require.NoError(t, err)
	require.Nil(t, result)

	// No record should be added if that was a repo.archived event
	msg = &security_center.SecurityFeatureRepoUpdate{
		Repository: &v1_entities.Repository{
			Id:               int64(expectedRepoID),
			OrganizationId:   wrapperspb.Int64(2),
			DefaultBranchRef: []byte("refs/heads/master"),
		},
		SourceEvent: "repo.archived",
		SecurityFeatureDetails: []*security_center.SecurityFeatureRepoUpdate_SecurityFeatureDetail{
			{
				SecurityFeature: v1_entities.SecurityFeature_CODE_SCANNING,
				FeatureVisible:  true,
			},
		},
	}
	err = consumer.RepoUpdate(ctx, msg, timestamppb.Now())
	require.NoError(t, err)
	result, err = rs.Find(ctx, expectedRepoID)
	require.NoError(t, err)
	require.Nil(t, result)

	// No record should be added if that was a repo.unarchived event
	msg = &security_center.SecurityFeatureRepoUpdate{
		Repository: &v1_entities.Repository{
			Id:               int64(expectedRepoID),
			OrganizationId:   wrapperspb.Int64(2),
			DefaultBranchRef: []byte("refs/heads/master"),
		},
		SourceEvent: "repo.unarchived",
		SecurityFeatureDetails: []*security_center.SecurityFeatureRepoUpdate_SecurityFeatureDetail{
			{
				SecurityFeature: v1_entities.SecurityFeature_CODE_SCANNING,
				FeatureVisible:  true,
			},
		},
	}
	err = consumer.RepoUpdate(ctx, msg, timestamppb.Now())
	require.NoError(t, err)
	result, err = rs.Find(ctx, expectedRepoID)
	require.NoError(t, err)
	require.Nil(t, result)

	// Record should not be updated if message processing is delayed
	dbtest.RequireCreate(t, db, &ts.Repository{
		RepositoryID:    expectedRepoID,
		OwnerID:         2,
		SourceUpdatedAt: sqltime.Time{Time: time.Now().Add(time.Hour)},
		DefaultRef:      []byte("refs/heads/master"),
	})

	msg = &security_center.SecurityFeatureRepoUpdate{
		Repository: &v1_entities.Repository{
			Id:               int64(expectedRepoID),
			OrganizationId:   wrapperspb.Int64(0),
			DefaultBranchRef: []byte("refs/heads/master"),
		},
		SecurityFeatureDetails: []*security_center.SecurityFeatureRepoUpdate_SecurityFeatureDetail{
			{
				SecurityFeature: v1_entities.SecurityFeature_CODE_SCANNING,
				FeatureVisible:  true,
			},
		},
	}

	err = consumer.RepoUpdate(ctx, msg, timestamppb.Now())
	require.NoError(t, err)
	result, err = rs.Find(ctx, expectedRepoID)
	require.NoError(t, err)
	require.Equal(t, result.OwnerID, ts.OwnerEID(2))
}

func TestRepoEventProcessorMissingFields(t *testing.T) {
	db, ctx, _, _, rs, consumer := setup(t)

	// Add an entry for the repo into the repositories table so the processor doesn't return early
	updatedAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	defaultRef := []byte("refs/heads/main")
	repo1 := &ts.Repository{RepositoryID: 1, OwnerID: 1, SourceUpdatedAt: updatedAt, DefaultRef: defaultRef}
	dbtest.RequireCreate(t, db, repo1)

	// missing repository
	msg := &security_center.SecurityFeatureRepoUpdate{
		SecurityFeatureDetails: []*security_center.SecurityFeatureRepoUpdate_SecurityFeatureDetail{
			{
				SecurityFeature: v1_entities.SecurityFeature_CODE_SCANNING,
				FeatureVisible:  true,
			},
		},
	}
	err := consumer.RepoUpdate(ctx, msg, timestamppb.Now())
	require.Error(t, err)
	require.ErrorIs(t, err, ErrMissingField)

	// missing security features
	msg = &security_center.SecurityFeatureRepoUpdate{
		Repository: &v1_entities.Repository{
			Id:               int64(1),
			OrganizationId:   wrapperspb.Int64(4),
			DefaultBranchRef: defaultRef,
		},
	}
	err = consumer.RepoUpdate(ctx, msg, timestamppb.Now())
	require.Error(t, err)
	require.ErrorIs(t, err, ErrMissingField)

	// missing code scanning details
	msg = &security_center.SecurityFeatureRepoUpdate{
		Repository: &v1_entities.Repository{
			Id:               int64(1),
			OrganizationId:   wrapperspb.Int64(4),
			DefaultBranchRef: defaultRef,
		},
		SecurityFeatureDetails: []*security_center.SecurityFeatureRepoUpdate_SecurityFeatureDetail{
			{
				SecurityFeature: v1_entities.SecurityFeature_DEPENDABOT_ALERTS,
				FeatureVisible:  true,
			},
		},
	}
	err = consumer.RepoUpdate(ctx, msg, timestamppb.Now())
	require.Error(t, err)
	require.ErrorIs(t, err, ErrMissingField)

	// missing organization id
	msg = &security_center.SecurityFeatureRepoUpdate{
		Repository: &v1_entities.Repository{
			Id:               int64(1),
			DefaultBranchRef: defaultRef,
		},
		SecurityFeatureDetails: []*security_center.SecurityFeatureRepoUpdate_SecurityFeatureDetail{
			{
				SecurityFeature: v1_entities.SecurityFeature_CODE_SCANNING,
				FeatureVisible:  true,
			},
		},
	}
	err = consumer.RepoUpdate(ctx, msg, timestamppb.Now())
	require.Error(t, err)
	require.ErrorIs(t, err, ErrMissingField)

	// missing default branch ref
	// these can happen e.g. for repos without commits, so we instead write the empty string
	// to the table.
	msg = &security_center.SecurityFeatureRepoUpdate{
		Repository: &v1_entities.Repository{
			Id:             int64(1),
			OrganizationId: wrapperspb.Int64(4),
		},
		SecurityFeatureDetails: []*security_center.SecurityFeatureRepoUpdate_SecurityFeatureDetail{
			{
				SecurityFeature: v1_entities.SecurityFeature_CODE_SCANNING,
				FeatureVisible:  true,
			},
		},
	}
	now := timestamppb.Now()
	// TODO: here we index docouments, but that doesnt trigger because there are no alerts.

	err = consumer.RepoUpdate(ctx, msg, now)
	require.NoError(t, err)
	result, err := rs.Find(ctx, ts.RepositoryEID(1))
	require.NotNil(t, result)
	require.NoError(t, err)
	require.Equal(t, []byte(""), result.DefaultRef)
}
