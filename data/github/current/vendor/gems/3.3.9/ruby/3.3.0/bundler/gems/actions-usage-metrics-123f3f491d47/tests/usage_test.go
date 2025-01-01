package tests

import (
	"context"
	"testing"
	"time"

	"github.com/github/actions-usage-metrics/internal/utils"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/stretchr/testify/assert"
)

const twirpUsageApiPath = "/twirp/actions_usage_metrics.api.v1.UsageApi/GetUsageByRepoWorkflowRunner"

var fakeDate = time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)

func TestUsageApiReturnsData(t *testing.T) {
	dateRange := proto.DateRangeType_DATE_RANGE_TYPE_LATEST_MONTH
	limit := uint64(10)
	offset := uint64(0)
	options := proto.RequestOptions{
		Scope:     utils.GetScopeFromOwnerId(1),
		DateRange: &dateRange,
		Limit:     &limit,
		Offset:    &offset,
	}

	client := GetTwirpClient(t)
	_, err := client.GetUsageByRepoWorkflowRunner(context.Background(), &proto.GetUsageByRepoWorkflowRunnerRequest{
		RequestOptions: &options,
	})

	assert.NoError(t, err, "api call should return real data")
}
