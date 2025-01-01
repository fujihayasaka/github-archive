package api

import (
	"fmt"
	"testing"
	"time"

	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	timestamppb "google.golang.org/protobuf/types/known/timestamppb"
)

var TestNow, _ = time.Parse(time.DateTime, "2024-04-15 15:04:05")

type TestClock struct{}

func (c *TestClock) Now() time.Time {
	return TestNow
}

func TestGetKustoDateRange(t *testing.T) {
	customStart := ParseDate("2024-04-15")
	customEnd := ParseDate("2024-05-21")
	customTimeRange := proto.DateRange{Start: timestamppb.New(customStart), End: timestamppb.New(customEnd)}
	var tests = []struct {
		protoDateRangeType proto.DateRangeType
		expectedStart      time.Time
		expectedEnd        time.Time
	}{
		{proto.DateRangeType_DATE_RANGE_TYPE_LATEST_MONTH, ParseDate("2024-04-01"), TestNow},
		{proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH, ParseDate("2024-03-01"), ParseDate("2024-03-31")},
		{proto.DateRangeType_DATE_RANGE_TYPE_CURRENT_WEEK, ParseDate("2024-04-15"), TestNow},
		{proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS, ParseDate("2024-03-16"), TestNow},
		{proto.DateRangeType_DATE_RANGE_TYPE_LAST_90_DAYS, ParseDate("2024-01-16"), TestNow},
		{proto.DateRangeType_DATE_RANGE_TYPE_LAST_YEAR, ParseDate("2023-04-01"), TestNow},
		{proto.DateRangeType_DATE_RANGE_TYPE_CUSTOM, ParseDate("2024-04-15"), ParseDate("2024-05-21")},
	}

	for _, tt := range tests {
		t.Run(fmt.Sprintf("%s %v %v", tt.protoDateRangeType.String(), tt.expectedStart.Format(time.DateOnly), tt.expectedEnd.Format(time.DateOnly)), func(t *testing.T) {
			timeRange, err := getKustoDateRange(tt.protoDateRangeType, &TestClock{}, &customTimeRange)
			if err != nil {
				t.Errorf("unexpected error: %v", err)
			}
			if timeRange.StartTime.AsTime() != tt.expectedStart {
				t.Errorf("expected start time %v, got %v", tt.expectedStart, timeRange.StartTime.AsTime())
			}
			if timeRange.EndTime.AsTime() != tt.expectedEnd {
				t.Errorf("expected end time %v, got %v", tt.expectedEnd, timeRange.EndTime.AsTime())
			}
		})
	}
}

func ParseDate(date string) time.Time {
	parsed, ok := time.Parse(time.DateOnly, date)
	if ok != nil {
		panic("bad date")
	}
	return parsed
}
