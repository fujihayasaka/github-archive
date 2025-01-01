package delivery_processor_test

import (
	"context"
	"strings"
	"testing"
	"time"

	v0 "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/delivery_processor"
	"github.com/github/turboscan/ts/hydro/consumers"
	"github.com/github/turboscan/ts/mocks"
	"github.com/github/turboscan/ts/mysql/delivery"
	"github.com/github/turboscan/ts/test_helpers"
	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/google/uuid"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
	"google.golang.org/protobuf/proto"
)

func TestCreateReturnMessage(t *testing.T) {
	db := dbtest.RequireConnection(t)
	deliveryService := delivery.NewService(db)

	startTime := &timestamp.Timestamp{Seconds: time.Now().Unix()}

	in := &v0.Analysis{
		RepositoryId:          123,
		SarifUri:              "/sarif/path.tar.gz",
		CommitOid:             "1234567890abcdef1234567890abcdef12345678",
		Ref:                   []byte("refs/heads/main"),
		AnalysisName:          "CodeQL",
		Environment:           "{\"TESTING\":\"123\"}",
		CheckoutUri:           "",
		WorkflowRunId:         123123,
		WorkflowRunAttempt:    1234,
		AnalysisKey:           "codeql",
		RequestId:             "7A0D:4163:5B5957:BA469F:652E5A0C",
		RepoNwo:               "github/code-scanning",
		OwnerId:               456,
		CheckRunIds:           []uint64{1111},
		SourceRepositoryId:    123,
		Tools:                 []*v0.Analysis_Tool{},
		SarifId:               uuid.NewString(),
		OutdatedConfiguration: &v0.Analysis_OutdatedConfiguration{},
		TrackStatus:           true,
		BuildStartAt:          startTime,
		UploadStartedAt:       startTime,
		UploadFinishedAt:      startTime,
		HydroEnqueuedAt:       startTime,
	}

	// convert to delivery
	d, err := consumers.DeliveryFromProto(in)
	require.NoError(t, err)
	ctx := context.Background()

	// save delivery
	require.NoError(t, deliveryService.CreateDelivery(ctx, d))

	var deliveries []*ts.Delivery

	// reload delivery
	require.NoError(t, db.Find(&deliveries).Error)
	require.Equal(t, 1, len(deliveries))
	d = deliveries[0]

	// build hydro message
	out := delivery_processor.CreateReturnMessage([]*ts.Analysis{}, d)

	require.Equal(t, in, out)
}

func TestNewTombstoneAnalysisCanPublishStatus(t *testing.T) {
	repoID := ts.RepositoryEID(123)
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()

	pub := mocks.NewMockAnalysisPublisher(mockCtrl)
	p := mocks.NewMockProcessor(mockCtrl)
	s := mocks.NewMockStatusService(mockCtrl)
	deliveryService := mocks.NewMockDeliveryService(mockCtrl)
	dp := delivery_processor.NewDeliveryProcessor(deliveryService, p, pub, s, 100*time.Second)

	ref := []byte("refs/heads/branch")
	sha := ts.ToSha(strings.Repeat("a", 40))
	delivery := &ts.Delivery{
		RepositoryID: repoID,
		SarifPath:    "example.sarif",
		CommitOid:    sha,
		Ref:          ref,
		AnalysisKey:  "woot",
		CheckoutURI:  "",
		CheckRunIds:  []uint64{123},
		OutdatedConfiguration: ts.OutdatedConfiguration{
			ToolName: "CodeQL",
			Category: "test",
		},
	}

	tombstone_msg := &v0.Analysis{}

	returnMsg, _ := proto.Clone(tombstone_msg).(*v0.Analysis)
	returnMsg.Tools = []*v0.Analysis_Tool{{Name: "CodeQL", ToolId: 1}}

	analysis := &ts.Analysis{
		Tool: &ts.Tool{CanonicalName: "CodeQL", ID: 1},
	}

	first := deliveryService.EXPECT().NextDelivery(gomock.Any(), repoID).Return(delivery, nil)
	second := deliveryService.EXPECT().NextDelivery(gomock.Any(), repoID).Return(nil, gorm.ErrRecordNotFound)
	gomock.InOrder(
		first,
		second,
	)

	deliveryService.EXPECT().WithLockedDelivery(gomock.Any(), delivery, gomock.Any()).DoAndReturn(func(ctx context.Context, delivery *ts.Delivery, fn func(context.Context) error) error {
		return fn(ctx)
	})

	p.EXPECT().
		ProcessNewDelivery(gomock.Any(), delivery).
		Return([]*ts.Analysis{analysis}, nil).Times(1)
	pub.EXPECT().
		ProcessedAnalysis(gomock.Any(), gomock.Any()).Times(1)

	s.EXPECT().PublishStatusIfChanged(gomock.Any(), repoID, ts.EnablementReason_RECEIVED_ANALYSIS, ref, test_helpers.PointerTo(false))

	require.NoError(t, dp.ProcessDeliveries(ctx, delivery.RepositoryID, 0))
}

func TestDoubleDeliveryCheck(t *testing.T) {
	repoID := ts.RepositoryEID(123)
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()

	pub := mocks.NewMockAnalysisPublisher(mockCtrl)
	p := mocks.NewMockProcessor(mockCtrl)
	s := mocks.NewMockStatusService(mockCtrl)
	deliveryService := mocks.NewMockDeliveryService(mockCtrl)
	dp := delivery_processor.NewDeliveryProcessor(deliveryService, p, pub, s, 100*time.Second)

	ref := []byte("refs/heads/branch")
	sha := ts.ToSha(strings.Repeat("a", 40))
	delivery := &ts.Delivery{
		RepositoryID: repoID,
		SarifPath:    "example.sarif",
		CommitOid:    sha,
		Ref:          ref,
		AnalysisKey:  "woot",
		CheckoutURI:  "",
		CheckRunIds:  []uint64{123},
		OutdatedConfiguration: ts.OutdatedConfiguration{
			ToolName: "CodeQL",
			Category: "test",
		},
	}

	tombstone_msg := &v0.Analysis{}

	returnMsg, _ := proto.Clone(tombstone_msg).(*v0.Analysis)
	returnMsg.Tools = []*v0.Analysis_Tool{{Name: "CodeQL", ToolId: 1}}

	analysis := &ts.Analysis{
		Tool: &ts.Tool{CanonicalName: "CodeQL", ID: 1},
	}

	first := deliveryService.EXPECT().NextDelivery(gomock.Any(), repoID).Return(delivery, nil)
	second := deliveryService.EXPECT().NextDelivery(gomock.Any(), repoID).Return(delivery, nil)
	gomock.InOrder(
		first,
		second,
	)

	firstWithLocked := deliveryService.EXPECT().WithLockedDelivery(gomock.Any(), delivery, gomock.Any()).DoAndReturn(func(ctx context.Context, delivery *ts.Delivery, fn func(context.Context) error) error {
		return fn(ctx)
	})
	secondtWithLocked := deliveryService.EXPECT().WithLockedDelivery(gomock.Any(), delivery, gomock.Any()).DoAndReturn(func(ctx context.Context, delivery *ts.Delivery, fn func(context.Context) error) error {
		return fn(ctx)
	})

	gomock.InOrder(
		firstWithLocked,
		secondtWithLocked,
	)

	p.EXPECT().
		ProcessNewDelivery(gomock.Any(), delivery).
		Return([]*ts.Analysis{analysis}, nil).Times(1)
	pub.EXPECT().
		ProcessedAnalysis(gomock.Any(), gomock.Any()).Times(1)

	s.EXPECT().PublishStatusIfChanged(gomock.Any(), repoID, ts.EnablementReason_RECEIVED_ANALYSIS, ref, test_helpers.PointerTo(false))

	require.ErrorIs(t, dp.ProcessDeliveries(ctx, delivery.RepositoryID, 0), delivery_processor.ErrSameDelivery)
}
