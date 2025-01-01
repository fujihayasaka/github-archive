package consumers

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
	"google.golang.org/protobuf/proto"

	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/mock"
	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	hydrolib "github.com/github/hydro-client-go/v7/pkg/hydro"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts/hydro/topics"
	"github.com/github/turboscan/ts/mocks"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
)

func TestErrorMarshal(t *testing.T) {
	ctx := context.Background()

	handler := &AnalysisEventProcessor{}

	en := &envelope.Envelope{Message: []byte{0x42}}
	_, err := proto.Marshal(en)
	require.NoError(t, err)

	err = handler.ProcessEnvelope(ctx, en, topics.NewAnalysis)
	require.Regexp(t, "unmarshalling analysis message: proto:(\u00a0| )cannot parse invalid wire-format data", err.Error())
}

func TestNewAnalysisAqueduct(t *testing.T) {
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	deliveryService := mocks.NewMockDeliveryService(mockCtrl)

	mockAqueduct := &aqueduct.AqueductMock{}
	handler := &AnalysisEventProcessor{
		aqueduct:            mockAqueduct,
		deliveryCreator:     deliveryService,
		maxRetryElapsedTime: 10 * time.Millisecond,
		retryDelay:          1 * time.Microsecond,
	}

	msg := &tshydro.Analysis{
		RepositoryId: 42,
		SarifUri:     "example.sarif",
		CommitOid:    strings.Repeat("a", 40),
		Ref:          []byte("refs/heads/branch"),
		AnalysisKey:  "woot",
		Environment:  "",
		CheckoutUri:  "",
		CheckRunIds:  []uint64{123},
	}

	returnMsg, _ := proto.Clone(msg).(*tshydro.Analysis)
	returnMsg.Tools = []*tshydro.Analysis_Tool{{Name: "CodeQL", ToolId: 1}}

	deliveryService.EXPECT().CreateDelivery(gomock.Any(), gomock.Any()).Return(nil)
	require.NoError(t, handler.NewAnalysis(ctx, msg))
	require.Equal(t, 1, len(mockAqueduct.EnqueuedJobs()))
}

func TestHandleError(t *testing.T) {
	emptyExporterFunc := func(ctx context.Context, data []byte) error {
		return nil
	}
	exporter := mock.NewExporter(emptyExporterFunc)
	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication("turboscan-test"),
	)
	require.NoError(t, err)

	ctx := appctx.WithReporter(context.Background(), reporter)

	handler := &AnalysisEventProcessor{}

	// Context Deadline
	ctxD, ctxDCancel := context.WithDeadline(ctx, time.Now().Add(-1))
	defer ctxDCancel()
	ctxErr := handler.HandleError(ctxD, nil, nil)
	require.Equal(t, ctxErr, context.DeadlineExceeded)

	// Context Cancel
	ctxC, cancel := context.WithCancel(ctx)
	cancel()
	ctxErr = handler.HandleError(ctxC, nil, nil)
	require.Equal(t, ctxErr, context.Canceled)

	// Do not retry in other cases
	msg := hydrolib.Message{}
	err = handler.HandleError(ctx, errors.New("test"), &msg)
	require.NoError(t, err)

}
