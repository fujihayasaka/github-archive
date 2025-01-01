package helpers

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/log/logtest"
	"github.com/github/github-telemetry-go/telemetry"
	statsmocks "github.com/github/go-stats/mocks"
	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

// Contains is a pegomock matcher that checks if the actual value contains the expected value
func Contains[T any](value T) T {
	pegomock.RegisterMatcher(&ContainsMatchers{Value: value})
	var t T
	return t
}

// ContainsMatchers implements pegomock.ArgumentMatcher.
type ContainsMatchers struct {
	Value  pegomock.Param
	actual pegomock.Param
	sync.Mutex
}

// String implements pegomock.ArgumentMatcher.
func (m *ContainsMatchers) String() string {
	return fmt.Sprintf("contains(%v)", &m.Value)
}

// Matches implements pegomock.ArgumentMatcher.
// It checks if the actual value contains the expected value for types PartitionKey and string
func (m *ContainsMatchers) Matches(param pegomock.Param) bool {
	m.Lock()
	defer m.Unlock()

	var r bool
	m.actual = param
	valueStr := fmt.Sprintf("%v", m.Value)
	valueStr = strings.Trim(valueStr, "[{}]")
	k, ok := param.(azcosmos.PartitionKey)
	if ok {
		s := fmt.Sprintf("%v", k)
		s = strings.Trim(s, "[{}]")
		r = strings.Contains(s, valueStr)
	} else {
		s := fmt.Sprintf("%v", param)
		r = strings.Contains(s, valueStr)
	}
	return r
}

// FailureMessage implements pegomock.ArgumentMatcher.
func (m *ContainsMatchers) FailureMessage() string {
	return fmt.Sprintf("Expected actual %v to contain %v", &m.actual, &m.Value)
}

func SetupMocks(t *testing.T) (*fakes.MockCosmosConnection, *telemetry.Provider, *statsmocks.Client, log.Logger, *fakes.MockDatabase) {
	mocker := pegomock.WithT(t)
	fakeContainer := fakes.NewMockCosmosConnection(mocker)

	telem, err := telemetry.NewFromEnv()
	assert.NoError(t, err)
	mockStatter := statsmocks.Client{}
	mockStatter.Mock.On("WithTags", mock.AnythingOfType("stats.Tags")).Return(&mockStatter)
	mockStatter.Mock.On("Distribution", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("float64")).Return(nil)
	mockStatter.Mock.On("Counter", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Return(nil)
	mockStatter.Mock.On("Timing", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("time.Duration")).Return(nil)
	logger := log.NewNullLogger()
	mockDB := &fakes.MockDatabase{}
	return fakeContainer, telem, &mockStatter, logger, mockDB
}

// MakePagerWithData creates a pager with the given Item data
func MakePagerWithData[T any](t *testing.T, data []*T) *runtime.Pager[azcosmos.QueryItemsResponse] {
	itemsToBeReturned := make([][]byte, 0)
	for _, item := range data {
		j, err := json.Marshal(&item)
		assert.NoError(t, err)
		itemsToBeReturned = append(itemsToBeReturned, j)
	}

	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: itemsToBeReturned}, nil
		},
	})
	return pager
}

// This meant to be a holder as a type constraint for any model implements GetUsageAt()
type modelsWithUsageAt interface {
	GetUsageAt() *timestamp.Timestamp
}

// WithinTimeUsageAt checks if the actual usage is within the threshold of the expected usage
func WithinTimeUsageAt[T modelsWithUsageAt](expectedUsage, actualUsage T, threshold time.Duration) bool {
	timeDiff := expectedUsage.GetUsageAt().AsTime().Sub(actualUsage.GetUsageAt().AsTime())
	return timeDiff < threshold
}

func NewTestLogger(t *testing.T) (log.Logger, *logtest.Buffer) {
	return logtest.NewTestLogger(t)
}
