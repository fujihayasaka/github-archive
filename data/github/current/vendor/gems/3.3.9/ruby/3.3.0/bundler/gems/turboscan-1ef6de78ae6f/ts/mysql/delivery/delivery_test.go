package delivery

import (
	"context"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/aws/smithy-go/ptr"
	"github.com/google/uuid"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/transforms"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
)

func testDelivery(repositoryID ts.RepositoryEID) *ts.Delivery {
	d := &ts.Delivery{
		RepositoryID:       repositoryID,
		SourceRepositoryID: repositoryID,
		Ref:                []byte("ref"),
		CommitOid:          "commitoid",
		Environment:        ts.AnalysisEnv{},
		Complete:           false,
		CheckRunIds:        ts.CheckRunIds{},
	}

	return d
}

func processDeliveryQueue(t *testing.T, ctx context.Context, ds *Service, nWorkersPerRepo int, repoIDs []ts.RepositoryEID) []ts.DeliveryID {
	t.Helper()
	// spin up n Workers and have them all attempt to lock the delivery at the same time
	// only one should ever 'win' for each repository ID
	var wg sync.WaitGroup
	wg.Add(nWorkersPerRepo * len(repoIDs))

	var mutex sync.Mutex
	var found []ts.DeliveryID

	for i := 0; i < nWorkersPerRepo*len(repoIDs); i++ {
		repoID := repoIDs[i%len(repoIDs)]
		go func() {
			defer wg.Done()

			for {
				d, err := ds.NextDelivery(ctx, repoID)
				// no work left to do
				if errors.Is(err, gorm.ErrRecordNotFound) {
					return
				}
				require.NoError(t, err)
				lockErr := ds.WithLockedDelivery(ctx, d, func(ctx context.Context) error {
					mutex.Lock()
					// perform the append inside a critical region so two goroutines do not attempt to
					// append this slice at the same time
					found = append(found, d.ID)
					mutex.Unlock()
					return ds.CompleteDelivery(ctx, d)
				})
				// delivery is already in progress
				if errors.Is(lockErr, ErrDeliveryLocked) {
					return
				}
				require.NoError(t, lockErr)
			}
		}()
	}
	wg.Wait()
	return found
}

func TestCreateSuccessfulDelivery(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ds := NewService(db)
	ctx := context.Background()

	repoID := ts.RepositoryEID(42)
	d := testDelivery(repoID)

	err := ds.CreateDelivery(ctx, d)

	require.NoError(t, err)
	require.NotNil(t, d.ID)

	var deliveries []ts.Delivery
	db.Find(&deliveries)
	require.Equal(t, 1, len(deliveries))
	require.False(t, deliveries[0].Complete)
	require.False(t, deliveries[0].Failed)

	err = ds.CompleteDelivery(ctx, d)
	require.NoError(t, err)

	db.Find(&deliveries)
	require.Equal(t, 1, len(deliveries))
	require.True(t, deliveries[0].Complete)
	require.False(t, deliveries[0].Failed)
}

func TestDeliveryCheckRunIds(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ds := NewService(db)
	ctx := context.Background()

	repoID := ts.RepositoryEID(42)
	d1 := testDelivery(repoID)
	d1.CheckRunIds = ts.CheckRunIds{1, 2, 3}
	d1.SarifID = "test-1"
	require.NoError(t, ds.CreateDelivery(ctx, d1))
	require.NotNil(t, d1.ID)

	d2 := testDelivery(repoID)
	d2.CheckRunIds = ts.CheckRunIds(nil)
	d2.SarifID = "test-2"
	require.NoError(t, ds.CreateDelivery(ctx, d2))
	require.NotNil(t, d2.ID)

	d3 := testDelivery(repoID)
	d3.CheckRunIds = ts.CheckRunIds{}
	d3.SarifID = "test-3"
	require.NoError(t, ds.CreateDelivery(ctx, d3))
	require.NotNil(t, d3.ID)

	var deliveries []*ts.Delivery

	require.NoError(t, db.Find(&deliveries).Error)
	require.Equal(t, 3, len(deliveries))

	byID := transforms.IndexBy(deliveries, func(d *ts.Delivery) ts.DeliveryID {
		return d.ID
	})

	require.Equal(t, ts.CheckRunIds{1, 2, 3}, byID[d1.ID].CheckRunIds)
	require.Equal(t, ts.CheckRunIds{}, byID[d2.ID].CheckRunIds)
	require.Equal(t, ts.CheckRunIds{}, byID[d3.ID].CheckRunIds)
}

func TestDeliveryQueue(t *testing.T) {
	db := dbtest.RequireConnectionWithoutTransaction(t)
	// db.LogMode(true)
	ds := NewService(db)
	ctx := context.Background()

	repoID := ts.RepositoryEID(42)

	d1 := testDelivery(repoID)
	d1.ProcessingStartedAt = ptr.Time(time.Now())

	d2 := testDelivery(repoID)
	d2.ProcessingStartedAt = ptr.Time(time.Now())
	d2.CommitOid = "deadbeef2"
	d2.SarifID = "test_delivery_2"

	repoID2 := ts.RepositoryEID(43)
	d3 := testDelivery(repoID2)
	d3.ProcessingStartedAt = ptr.Time(time.Now())

	require.NoError(t, ds.CreateDelivery(ctx, d1))
	require.NoError(t, ds.CreateDelivery(ctx, d2))
	require.NoError(t, ds.CreateDelivery(ctx, d3))

	var deliveries []*ts.Delivery
	require.NoError(t, db.Find(&deliveries).Error)
	require.Equal(t, 3, len(deliveries))
	require.False(t, deliveries[0].Complete)
	require.False(t, deliveries[0].Failed)

	found := processDeliveryQueue(t, ctx, ds, 10, []ts.RepositoryEID{repoID, repoID2})

	require.ElementsMatch(t, transforms.Map(deliveries, func(d *ts.Delivery) ts.DeliveryID { return d.ID }), found)
	require.Len(t, found, len(deliveries))

	_, deliveryErr := ds.NextDelivery(ctx, repoID)
	require.ErrorIs(t, deliveryErr, gorm.ErrRecordNotFound)
}

func TestDeliveryQueueMaxLockedTime(t *testing.T) {
	db := dbtest.RequireConnectionWithoutTransaction(t)
	maxLockedTime := 30 * time.Second
	ds := NewService(db, WithMaxLockedDuration(maxLockedTime))
	ctx := context.Background()

	repoID := ts.RepositoryEID(42)

	d1 := testDelivery(repoID)
	d1.ProcessingLock = ptr.String(uuid.NewString())
	d1.ProcessingStartedAt = ptr.Time(time.Now())

	d2 := testDelivery(repoID)
	d2.ProcessingStartedAt = ptr.Time(time.Now())
	d2.CommitOid = "deadbeef2"
	d2.SarifID = "test_delivery_2"

	// d3 stays locked as it has processing lock and updated_at set to now
	repoID2 := ts.RepositoryEID(43)
	d3 := testDelivery(repoID2)
	d3.ProcessingLock = ptr.String(uuid.NewString())

	require.NoError(t, ds.CreateDelivery(ctx, d1))
	require.NoError(t, ds.CreateDelivery(ctx, d2))
	require.NoError(t, ds.CreateDelivery(ctx, d3))

	var deliveries []*ts.Delivery
	require.NoError(t, db.Find(&deliveries, "repository_id = ?", repoID).Error)
	require.Equal(t, 2, len(deliveries))
	require.False(t, deliveries[0].Complete)
	require.False(t, deliveries[0].Failed)

	require.NoError(t, db.Model(d1).UpdateColumn("updated_at", time.Now().Add(-maxLockedTime)).Error)
	// This should already be the case for d3 but making it explicit
	require.NoError(t, db.Model(d3).UpdateColumn("updated_at", time.Now()).Error)

	found := processDeliveryQueue(t, ctx, ds, 10, []ts.RepositoryEID{repoID, repoID2})

	require.ElementsMatch(t, transforms.Map(deliveries, func(d *ts.Delivery) ts.DeliveryID { return d.ID }), found)
	require.Len(t, found, len(deliveries))

	_, deliveryErr := ds.NextDelivery(ctx, repoID)
	require.ErrorIs(t, deliveryErr, gorm.ErrRecordNotFound)
}

func TestCreateFailedDelivery(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ds := NewService(db)
	ctx := context.Background()

	repoID := ts.RepositoryEID(42)
	d := testDelivery(repoID)

	err := ds.CreateDelivery(ctx, d)
	require.NoError(t, err)
	require.NotNil(t, d.ID)

	var deliveries []ts.Delivery
	db.Find(&deliveries)
	require.Equal(t, 1, len(deliveries))
	require.False(t, deliveries[0].Complete)
	require.False(t, deliveries[0].Failed)

	d.Failed = true
	err = ds.CompleteDelivery(ctx, d)
	require.NoError(t, err)

	db.Find(&deliveries)
	require.Equal(t, 1, len(deliveries))
	require.True(t, deliveries[0].Complete)
	require.True(t, deliveries[0].Failed)
}

func TestCreateDuplicateDelivery(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ds := NewService(db)
	ctx := context.Background()

	repoID := ts.RepositoryEID(42)

	d1 := testDelivery(repoID)
	err := ds.CreateDelivery(ctx, d1)
	require.NoError(t, err)
	require.NotNil(t, d1.ID)

	d2 := testDelivery(repoID)
	err = ds.CreateDelivery(ctx, d2)
	require.NoError(t, err)
	require.Equal(t, d1.ID, d2.ID)

	var deliveries []ts.Delivery
	db.Find(&deliveries)
	require.Equal(t, 1, len(deliveries))
}

func TestDeliveryPersistence(t *testing.T) {
	// this test ensures that delivery records that have come from Kafka survive the serialization process

	db := dbtest.RequireConnection(t)

	now := sqltime.Now().Time

	// create a delivery with one of everything
	d := ts.Delivery{
		BaseModel: ts.BaseModel{
			UpdatedAt: sqltime.Now(),
			CreatedAt: sqltime.Now(),
		},
		CommitOid:          "deadbeef",
		ID:                 1,
		Ref:                []byte("refs/heads/main"),
		RepositoryID:       1,
		RepositoryNWO:      "repository/nwo",
		OwnerID:            1,
		SarifID:            "sarif-id",
		RequestID:          "request-id",
		AnalysisName:       "analysis-name",
		AnalysisKey:        "analysis-key",
		Environment:        ts.AnalysisEnv{"key": "value"},
		CheckoutURI:        "file://checkout-uri",
		BuildStartedAt:     ptr.Time(now),
		WorkflowRunID:      1,
		WorkflowRunAttempt: 1,
		UploadStartedAt:    ptr.Time(now),
		UploadFinishedAt:   ptr.Time(now),
		HydroEnqueuedAt:    ptr.Time(now),
		SarifPath:          "sarif/path.tgz",
		SourceRepositoryID: 1,
		OutdatedConfiguration: ts.OutdatedConfiguration{
			ToolName: "tool-name",
			Category: "category",
		},
		ProcessingLock:        ptr.String("processing-lock"),
		ProcessingStartedAt:   ptr.Time(now),
		ProcessingCompletedAt: ptr.Time(now),
		Complete:              true,
		Failed:                true,
		TrackStatus:           true,
		Origin:                ts.DeliveryOrigin_MANAGED,
		WorkflowPath:          []byte("/workflow"),
		CheckRunIds:           ts.CheckRunIds{1},
		AnalysisMessages:      []*ts.AnalysisMessage{},
	}

	// check every field has a value set
	for _, f := range reflect.VisibleFields(reflect.TypeOf(d)) {
		require.Falsef(t, reflect.ValueOf(d).FieldByName(f.Name).IsZero(), "Field %q should not be zero", f.Name)
	}

	require.NoError(t, db.Save(&d).Error)

	var out ts.Delivery

	require.NoError(t, db.Find(&out).Error)

	// gorm loads this as nil, that's fine
	d.AnalysisMessages = nil

	// check every field still has a value set
	require.Equal(t, d, out)
}

func TestErrosOnSuccessfulIncompleteDelivery(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ds := NewService(db)
	ctx := context.Background()

	repoID := ts.RepositoryEID(42)

	d := testDelivery(repoID)
	d.ProcessingStartedAt = ptr.Time(time.Now())
	err := ds.CreateDelivery(ctx, d)

	require.NoError(t, err)
	require.NotNil(t, d.ID)

	require.ErrorIs(t, ds.WithLockedDelivery(ctx, d, func(ctx context.Context) error {
		return nil
	}), ErrDeliveryNotCompleted)

}

func TestGetCodeqlRunDeliveries(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	s := NewService(db)

	repoID := ts.RepositoryEID(1)
	actionsWorkflowRunID := ts.WorkflowRunEID(2)

	deliveries, err := s.GetDeliveriesByWorkflowRunID(ctx, repoID, actionsWorkflowRunID)
	require.NoError(t, err)
	require.Empty(t, deliveries)

	workflow_delivery1 := &ts.Delivery{
		RepositoryID: repoID,
		Ref:          []byte("refs/heads/main"),
		CommitOid:    ts.ToSha("ae230d"),
		Environment: ts.AnalysisEnv{
			"language": "ruby",
		},
		WorkflowRunID: actionsWorkflowRunID,
	}

	workflow_delivery2 := &ts.Delivery{
		RepositoryID: repoID,
		Ref:          []byte("refs/heads/main"),
		CommitOid:    ts.ToSha("ae230d"),
		Environment: ts.AnalysisEnv{
			"language": "go",
		},
		WorkflowRunID: actionsWorkflowRunID,
	}

	nonworkflow_delivery := &ts.Delivery{
		RepositoryID: repoID,
		Ref:          []byte("refs/heads/main"),
		CommitOid:    ts.ToSha("ae230d"),
		Environment: ts.AnalysisEnv{
			"language": "go",
		},
		WorkflowRunID: ts.WorkflowRunEID(456),
	}

	dbtest.RequireCreate(t, db, workflow_delivery1)
	dbtest.RequireCreate(t, db, workflow_delivery2)
	dbtest.RequireCreate(t, db, nonworkflow_delivery)

	deliveries, err = s.GetDeliveriesByWorkflowRunID(ctx, repoID, actionsWorkflowRunID)

	require.NoError(t, err)
	require.Len(t, deliveries, 2)

	for _, d := range deliveries {
		require.Equal(t, repoID, d.RepositoryID)
		require.Equal(t, actionsWorkflowRunID, d.WorkflowRunID)
	}

}
