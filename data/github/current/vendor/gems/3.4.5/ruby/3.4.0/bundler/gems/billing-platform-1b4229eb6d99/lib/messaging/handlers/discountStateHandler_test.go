package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	stats "github.com/github/go-stats"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

func TestNewDiscountStateHandler_InitializedWithCorrectQueueName(t *testing.T) {
	handler := NewDiscountStateHandler(&HandlerParams{}, nil)
	assert.NotNil(t, handler)
	assert.Equal(t, handler.queueName, "discount-state-update")
}

func TestDiscountStateHandler_ProcessMessage(t *testing.T) {
	_, _, statter, logger, _ := helpers.SetupMocks(t)

	mockDiscountEngine := fakes.NewMockDiscountEngineInterface(pegomock.WithT(t))
	handler := NewDiscountStateHandler(&HandlerParams{statter: statter}, mockDiscountEngine)

	model := &models.UpdateDiscountStatePayload{
		// set the CreatedAt to be 1 minute in the past
		CreatedAt: time.Now().Add(-1 * time.Minute),
	}

	payload, err := json.Marshal(model)
	assert.Nil(t, err)

	rr := aqueduct.ReceiveResult{
		DeliveryAttempt: 1,
		Job:             aqueduct.Job{Payload: payload},
	}

	err = handler.ProcessMessage(context.Background(), logger, rr)
	assert.NoError(t, err)

	statter.AssertCalled(t, "Counter", "discount.state.update", stats.Tags{"delivery_attempt": fmt.Sprintf("%d", rr.DeliveryAttempt)}, int64(1))

	// Capture the actual duration passed to the Timing method
	var actualDuration time.Duration
	captureDuration := func(d time.Duration) bool {
		// Save the actual duration so we can assert on it in subsequent tests
		actualDuration = d
		return true
	}
	statter.AssertCalled(t, "Timing", "discount.state.apply_update_duration", stats.Tags{}, mock.MatchedBy(captureDuration))

	// Verify that the actual duration is >= 1 minute to account for possible variations in execution time
	expectedDuration := 1 * time.Minute
	assert.GreaterOrEqual(t, actualDuration.Seconds(), expectedDuration.Seconds(), "The duration should be >= 1 minute")
}
