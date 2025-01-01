package api

import (
	"fmt"
	"time"

	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/internal/kusto/query"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/querybuilder"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/internal/utils"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	timestamppb "google.golang.org/protobuf/types/known/timestamppb"
)

type TimeRange struct {
	StartTime timestamppb.Timestamp `json:"startTime"`
	EndTime   timestamppb.Timestamp `json:"endTime"`
}

// Note: To match existing behavior, the end time is the (start of) the day ending the period, not the start of the next period.
// e.g. for the month of April, the end time returned is 2024-04-30 00:00:00, not 2024-05-01 00:00:00
// In the Kusto query, we use endofday() to make sure we get everything for that day.
// Consider changing this after fully migrating to Kusto.
func getKustoDateRange(dateRange proto.DateRangeType, clock Clock, customDateRange *proto.DateRange) (TimeRange, error) {
	now := clock.Now().UTC()
	var start time.Time
	var end time.Time
	switch dateRange {
	case proto.DateRangeType_DATE_RANGE_TYPE_LATEST_MONTH:
		start = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
		end = now

	case proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH:
		start = time.Date(now.Year(), now.Month()-1, 1, 0, 0, 0, 0, now.Location())
		end = start.AddDate(0, 1, -1) // last day of previous month

	case proto.DateRangeType_DATE_RANGE_TYPE_CURRENT_WEEK:
		start = common.GetWeekStartDate(now)
		end = now

	case proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS:
		start = now.AddDate(0, 0, -30).Truncate(24 * time.Hour)
		end = now

	case proto.DateRangeType_DATE_RANGE_TYPE_LAST_90_DAYS:
		start = now.AddDate(0, 0, -90).Truncate(24 * time.Hour)
		end = now

	case proto.DateRangeType_DATE_RANGE_TYPE_LAST_YEAR:
		start = time.Date(now.Year()-1, now.Month(), 1, 0, 0, 0, 0, now.Location()) // First day of this month a year ago
		end = now

	case proto.DateRangeType_DATE_RANGE_TYPE_CUSTOM:
		start = utils.GetStartOfDay(customDateRange.GetStart().AsTime())
		end = utils.GetStartOfDay(customDateRange.GetEnd().AsTime())

	default:
		return TimeRange{}, fmt.Errorf("unsupported date range type: %v", dateRange)
	}

	return TimeRange{StartTime: *timestamppb.New(start), EndTime: *timestamppb.New(end)}, nil
}

func convertFiltersFromProto(filters []*proto.Filter) []querybuilder.KustoModelFilter {
	kustoFilters := make([]querybuilder.KustoModelFilter, 0, len(filters))

	filterConverter := common.FilterConverter{}
	for _, protoFilter := range filters {
		kustoFilter, err := filterConverter.Convert(protoFilter)
		if err != nil {
			log.WithError(err).Error("failed to convert filter",
				kvp.String(telemetry.FilterKey, protoFilter.Key),
				kvp.String(telemetry.FilterOperatorKey, protoFilter.Operator.String()))
			continue // Skip invalid filters
		}

		kustoFilters = append(kustoFilters, kustoFilter)
	}
	return kustoFilters
}

func getKustoCardinalityAggregateResponse(value int64) *proto.CardinalityField {
	// https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/hll-aggregation-function#estimation-accuracy
	// The algorithm includes some provisions for doing a perfect count (zero error), if the set cardinality is small enough:
	// When the accuracy level is 2, 8000 values are returned
	if value < 8000 {
		return &proto.CardinalityField{Count: uint64(value), Approximate: false}
	}

	return &proto.CardinalityField{Count: uint64(value), Approximate: true}
}

func convertOrderByWithSecondaryFromProto(primaryOrderBy *proto.OrderBy, secondaryOrderBy *proto.OrderBy) *[]querybuilder.OrderBy {
	primaryPtr := convertOrderByFromProto(primaryOrderBy)
	secondaryPtr := convertOrderByFromProto(secondaryOrderBy)

	if primaryPtr == nil {
		// If primary is nil, secondary should be nil as well
		return nil
	}

	primary := *primaryPtr

	orderBys := []querybuilder.OrderBy{primary}

	if secondaryPtr != nil {
		secondary := *secondaryPtr

		if secondary.Field != primary.Field {
			orderBys = append(orderBys, secondary)
		}
	}

	return &orderBys
}

func convertOrderByFromProto(orderBy *proto.OrderBy) *querybuilder.OrderBy {
	if orderBy == nil {
		return nil
	}

	converted := querybuilder.OrderBy{
		Field:     querybuilder.GetKustoField(orderBy.Field),
		Direction: querybuilder.OrderByDirection_DESC, // default in case unknown
	}

	if orderBy.Direction == proto.OrderByDirection_ORDER_BY_DIRECTION_ASC {
		converted.Direction = querybuilder.OrderByDirection_ASC
	}

	return &converted
}

func convertQueryOptionsFromRequestOptions(requestOptions *proto.RequestOptions, secondaryOrderBy *proto.OrderBy, kustoCfg config.KustoConfig) (*query.QueryOptions, error) {
	if requestOptions == nil {
		return nil, fmt.Errorf("No request options provided")
	}

	var startTime *time.Time = nil
	var endTime *time.Time = nil

	if requestOptions.DateRange != nil {
		kustoDateRange, err := getKustoDateRange(*requestOptions.DateRange, RealClock{}, requestOptions.CustomDateRange)
		if err != nil {
			return nil, fmt.Errorf("failed to get kusto date range: %w", err)
		}
		start := kustoDateRange.StartTime.AsTime()
		startTime = &start
		end := kustoDateRange.EndTime.AsTime()
		endTime = &end
	}

	var offsetLimit *querybuilder.OffsetLimit = nil
	if requestOptions.Offset != nil && requestOptions.Limit != nil {
		paging := querybuilder.OffsetLimit{Offset: *requestOptions.Offset, Limit: *requestOptions.Limit}
		offsetLimit = &paging
	}

	filters := convertFiltersFromProto(requestOptions.Filters)
	setMappedScope(requestOptions.Scope, kustoCfg)

	var search *query.Search = nil
	if requestOptions.Search != nil && requestOptions.SearchField != nil {
		search = &query.Search{Search: requestOptions.Search, Column: *requestOptions.SearchField}
	}

	orderBy := convertOrderByWithSecondaryFromProto(requestOptions.OrderBy, secondaryOrderBy)

	version := getProjectionVersion(requestOptions.ProjectionOptions)

	queryOptions := query.QueryOptions{
		Scope:       requestOptions.Scope,
		StartDay:    startTime,
		EndDay:      endTime,
		Filters:     &filters,
		OrderBy:     orderBy,
		OffsetLimit: offsetLimit,
		Search:      search,
		Version:     &version,
	}

	return &queryOptions, nil
}
