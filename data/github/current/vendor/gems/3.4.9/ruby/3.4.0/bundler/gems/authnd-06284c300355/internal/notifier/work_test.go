package notifier

import (
	"context"
	"testing"
	"time"

	"github.com/golang/mock/gomock"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/authnd/internal/common/models"
	schema "github.com/github/authnd/internal/common/publisher/hydro/schemas/authnd/v0"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/github/authnd/internal/mocks"
)

func TestWork_SuccessNoTokens(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	eventPublisher := mocks.NewMockPratEventPublisher(ctrl)

	testWork := &work{
		lookupTokens: func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
			return []*models.ProgrammaticAccessToken{}, nil
		},
		eventer: eventPublisher,
		timeout: 1 * time.Second,
	}

	ctx := commonTesting.NewLoggerContext(t)
	err := testWork.Do(ctx)
	assert.NoError(t, err)
}

func TestWork_SuccessMultipleBatches(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	eventPublisher := mocks.NewMockPratEventPublisher(ctrl)
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.MonalisaProgrammaticAccessToken, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Return(nil)
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Return(nil)
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.ExpiredProgrammaticAccessToken, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Return(nil)

	var batchNum int
	batches := [][]*models.ProgrammaticAccessToken{
		{
			testfixtures.MonalisaProgrammaticAccessToken,
			testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes,
		},
		{
			testfixtures.ExpiredProgrammaticAccessToken,
		},
	}
	lastIDs := []uint64{0, testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes.ID, testfixtures.ExpiredProgrammaticAccessToken.ID}
	testWork := &work{
		eventType: schema.ProgrammaticAccessEvent_ISSUED,
		lookupTokens: func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
			assert.Equal(t, lastIDs[batchNum], lastID)
			if batchNum >= len(batches) {
				return []*models.ProgrammaticAccessToken{}, nil
			}
			return batches[batchNum], nil
		},
		eventer: eventPublisher,
		markTokenEvents: func(c context.Context, ids []uint64) error {
			desiredIDs := make([]uint64, len(batches[batchNum]))
			for ix, token := range batches[batchNum] {
				desiredIDs[ix] = token.ID
			}
			assert.Equal(t, desiredIDs, ids)
			// move onto the next batch after this query
			batchNum++
			return nil
		},
		timeout:   1 * time.Second,
		batchSize: 2,
	}
	if commonTesting.IsProximaMode() {
		addTenantAttributes(testWork)
	}

	ctx := commonTesting.NewLoggerContext(t)
	err := testWork.Do(ctx)
	assert.NoError(t, err)
}

func TestWork_SuccessMixedHydroResults(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	eventPublisher := mocks.NewMockPratEventPublisher(ctrl)
	// this token fails
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.MonalisaProgrammaticAccessToken, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Return(errors.New("transient hydro error"))
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Return(nil)
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.ExpiredProgrammaticAccessToken, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Return(nil)

	var batchNum int
	batches := [][]*models.ProgrammaticAccessToken{
		{
			testfixtures.MonalisaProgrammaticAccessToken,
			testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes,
		},
		{
			testfixtures.ExpiredProgrammaticAccessToken,
		},
	}
	failsHydro := [][]bool{
		{true, false},
		{false},
	}
	lastIDs := []uint64{0, testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes.ID, testfixtures.ExpiredProgrammaticAccessToken.ID}
	testWork := &work{
		eventType: schema.ProgrammaticAccessEvent_ISSUED,
		lookupTokens: func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
			assert.Equal(t, lastIDs[batchNum], lastID)
			if batchNum >= len(batches) {
				return []*models.ProgrammaticAccessToken{}, nil
			}
			return batches[batchNum], nil
		},
		eventer: eventPublisher,
		markTokenEvents: func(c context.Context, ids []uint64) error {
			desiredIDs := []uint64{}
			for ix, token := range batches[batchNum] {
				if !failsHydro[batchNum][ix] {
					desiredIDs = append(desiredIDs, token.ID)
				}
			}
			assert.Equal(t, desiredIDs, ids)
			// move onto the next batch after this query
			batchNum++
			return nil
		},
		timeout:   1 * time.Second,
		batchSize: 2,
	}
	if commonTesting.IsProximaMode() {
		addTenantAttributes(testWork)
	}

	ctx := commonTesting.NewLoggerContext(t)
	err := testWork.Do(ctx)
	assert.NoError(t, err)
}

func TestWork_FailureWholeBatchFails(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	eventPublisher := mocks.NewMockPratEventPublisher(ctrl)
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.MonalisaProgrammaticAccessToken, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Return(errors.New("persistent hydro erro"))
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Return(nil)
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.ExpiredProgrammaticAccessToken, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Return(errors.New("persistent hydro erro"))

	var batchNum int
	batches := [][]*models.ProgrammaticAccessToken{
		{
			testfixtures.MonalisaProgrammaticAccessToken,
			testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes,
		},
		{
			testfixtures.ExpiredProgrammaticAccessToken,
		},
	}
	failsHydro := [][]bool{
		{true, false},
		{true},
	}
	lastIDs := []uint64{0, testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes.ID}
	testWork := &work{
		eventType: schema.ProgrammaticAccessEvent_ISSUED,
		lookupTokens: func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
			assert.Equal(t, lastIDs[batchNum], lastID)
			if batchNum >= len(batches) {
				return []*models.ProgrammaticAccessToken{}, nil
			}
			return batches[batchNum], nil
		},
		eventer: eventPublisher,
		markTokenEvents: func(c context.Context, ids []uint64) error {
			desiredIDs := []uint64{}
			for ix, token := range batches[batchNum] {
				if !failsHydro[batchNum][ix] {
					desiredIDs = append(desiredIDs, token.ID)
				}
			}
			assert.Equal(t, desiredIDs, ids)
			// move onto the next batch after this query
			batchNum++
			return nil
		},
		timeout:   1 * time.Second,
		batchSize: 2,
	}
	if commonTesting.IsProximaMode() {
		addTenantAttributes(testWork)
	}

	ctx := commonTesting.NewLoggerContext(t)
	err := testWork.Do(ctx)
	require.Error(t, err)
	assert.EqualError(t, err, "failed to process any tokens in batch")
}

func TestWork_FailureShutdownDuringBatch(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx, cancel := context.WithCancel(commonTesting.NewLoggerContext(t))

	eventPublisher := mocks.NewMockPratEventPublisher(ctrl)
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.MonalisaProgrammaticAccessToken, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Do(func(arg0, arg1 interface{}) {
		// cancel the global context before returning
		cancel()
	}).Return(nil)
	// the request of the requests are cancelled by the hydro client
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Return(context.Canceled)
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.ExpiredProgrammaticAccessToken, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Return(context.Canceled)

	batch := []*models.ProgrammaticAccessToken{
		testfixtures.MonalisaProgrammaticAccessToken,
		testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes,
		testfixtures.ExpiredProgrammaticAccessToken,
	}
	desiredIDs := []uint64{testfixtures.MonalisaProgrammaticAccessToken.ID}
	testWork := &work{
		eventType: schema.ProgrammaticAccessEvent_ISSUED,
		lookupTokens: func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
			assert.Equal(t, uint64(0), lastID)
			return batch, nil
		},
		eventer: eventPublisher,
		markTokenEvents: func(c context.Context, ids []uint64) error {
			assert.Equal(t, desiredIDs, ids)
			return nil
		},
		timeout:   1 * time.Second,
		batchSize: 3,
	}
	if commonTesting.IsProximaMode() {
		addTenantAttributes(testWork)
	}

	err := testWork.Do(ctx)
	require.Error(t, err)
	assert.ErrorIs(t, err, context.Canceled)
}

func TestWork_FailureTimeout(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	eventPublisher := mocks.NewMockPratEventPublisher(ctrl)

	testWork := &work{
		lookupTokens: func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(10 * time.Millisecond):
				return nil, errors.New("a non-timeout error")
			}
		},
		eventer: eventPublisher,
		timeout: 1 * time.Millisecond,
	}

	ctx := commonTesting.NewLoggerContext(t)
	err := testWork.Do(ctx)
	assert.True(t, errors.Is(err, context.DeadlineExceeded), err)
}

func TestWork_FailureContextCancelled(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	eventPublisher := mocks.NewMockPratEventPublisher(ctrl)

	testWork := &work{
		lookupTokens: func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(10 * time.Millisecond):
				return nil, errors.New("a non-timeout error")
			}
		},
		eventer: eventPublisher,
		timeout: 20 * time.Millisecond,
	}

	ctx := commonTesting.NewLoggerContext(t)
	ctx, cancel := context.WithCancel(ctx)
	go func() {
		<-time.After(1 * time.Millisecond)
		cancel()
	}()

	err := testWork.Do(ctx)
	assert.True(t, errors.Is(err, context.Canceled), err)
}

func TestWork_FailureTokenLookup(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	eventPublisher := mocks.NewMockPratEventPublisher(ctrl)

	testWork := &work{
		lookupTokens: func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
			return nil, errors.New("failed to look up tokens")
		},
		eventer: eventPublisher,
		timeout: 20 * time.Millisecond,
	}

	ctx := commonTesting.NewLoggerContext(t)
	err := testWork.Do(ctx)
	require.Error(t, err)
	assert.EqualError(t, err, "failed to look up tokens")
}

func TestWork_FailureMarkTokenEvents(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	eventPublisher := mocks.NewMockPratEventPublisher(ctrl)
	eventPublisher.EXPECT().PublishEvent(gomock.Any(),
		toHydroEvent(testfixtures.MonalisaProgrammaticAccessToken, schema.ProgrammaticAccessEvent_ISSUED, ""),
	).Times(1).Return(nil)

	testWork := &work{
		eventType: schema.ProgrammaticAccessEvent_ISSUED,
		lookupTokens: func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
			return []*models.ProgrammaticAccessToken{testfixtures.MonalisaProgrammaticAccessToken}, nil
		},
		eventer: eventPublisher,
		markTokenEvents: func(c context.Context, ids []uint64) error {
			require.Len(t, ids, 1)
			assert.Equal(t, testfixtures.MonalisaProgrammaticAccessToken.ID, ids[0])
			return errors.New("failed to mark events for provided tokens")
		},
		timeout:   1 * time.Second,
		batchSize: 2,
	}
	if commonTesting.IsProximaMode() {
		addTenantAttributes(testWork)
	}

	ctx := commonTesting.NewLoggerContext(t)
	err := testWork.Do(ctx)
	require.Error(t, err)
	assert.EqualError(t, err, "failed to mark events for provided tokens")
}

func toHydroEvent(token *models.ProgrammaticAccessToken, eventType schema.ProgrammaticAccessEventEventType, eventReason string) schema.ProgrammaticAccessEvent {
	event := schema.ProgrammaticAccessEvent{
		ActorId:                int64(token.MintTokenCommon.ActorID),
		CredentialId:           int64(token.ID),
		AccessId:               int64(token.AccessID),
		CredentialSuffix:       string(token.TokenSuffix),
		CredentialIssuedAtUtc:  timestamppb.New(token.MintTokenCommon.IssuedAt),
		CredentialExpiresAtUtc: token.ExpiresAt.ToProto(),
		EventType:              eventType,
		EventReason:            eventReason,
		SendNotification:       true,
		CatalogService:         serviceName,
		RequestId:              JobID,
	}

	if commonTesting.IsProximaMode() {
		event.TenantId = int64(testfixtures.DefaultBusiness.ID)
	}

	return event
}

func addTenantAttributes(w *work) {
	w.isProxima = true
	w.businessIdForToken = func(ctx context.Context, token uint64) (uint64, error) {
		return uint64(testfixtures.DefaultBusiness.ID), nil
	}
}
