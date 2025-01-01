package telemetry

import (
	"context"
	"testing"

	mock_log "github.com/github/actions-usage-metrics/internal/mocks/telemetry"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
)

func TestWithContextNotAffectOriginalLogger(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()
	mockBaseLogger := mock_log.NewMockLogger(mockCtrl)

	// Create a logger (e.g. the shared/default logger telemetry.Logger)
	originalLogger, err := NewLogger(mockBaseLogger, nil)
	assert.NoError(t, err)

	// Create a context and add some logging fields
	savedField := kvp.String("key1", "value1")
	passedField := kvp.String("key2", "value2")
	ctx1 := AddLoggingFields(context.Background(), savedField)

	// Use the original logger with WithContext,
	mockBaseLogger.EXPECT().WithContext(gomock.Any()).Return(mockBaseLogger).Times(1) // expect a call to the base logger to add tracing fields
	mockBaseLogger.EXPECT().WithFields(savedField).Return(mockBaseLogger).Times(1)    // expect a call to the base logger to add our logging fields
	mockBaseLogger.EXPECT().Log(gomock.Any(), gomock.Any(), passedField).Times(1)
	originalLogger.WithContext(ctx1).Info("test", passedField)

	// Use the original logger without WithContext, expect on the underlying base logger that WithFields is never called and Log is called with only the explicit fields passed
	mockBaseLogger.EXPECT().Log(gomock.Any(), gomock.Any() /* no ctx1Field */)
	originalLogger.Info("test")
}
