package api

import (
	"context"
	"fmt"
	"time"

	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/internal/kusto"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/querybuilder"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/internal/utils"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/twitchtv/twirp"
	"golang.org/x/sync/errgroup"

	timestamppb "google.golang.org/protobuf/types/known/timestamppb"
)

// UsageApi implements the proto.UsageApi twirp interface used by the Monolith to query usage data.
type UsageApi struct {
	apiServerCfg config.ApiServerConfig
	kustoClient  *kusto.Client
	telem        *telemetry.Telemetry
}

var _ proto.UsageApi = (*UsageApi)(nil)

type GetItemsResult[TItem any] struct {
	Items      []TItem
	TotalItems uint64
	TimeRange  TimeRange
	DelayTimes common.KustoDelayTimes
}

var UsageDefaultOrderBy = proto.OrderBy{
	Field:     querybuilder.TotalMinutesFieldName.String(),
	Direction: proto.OrderByDirection_ORDER_BY_DIRECTION_DESC,
}

var PerformanceDefaultOrderBy = proto.OrderBy{
	Field:     querybuilder.AverageRunTime.String(),
	Direction: proto.OrderByDirection_ORDER_BY_DIRECTION_DESC,
}

func NewUsageApi(apiServerCfg config.ApiServerConfig, kustoClient *kusto.Client, telem *telemetry.Telemetry) *UsageApi {
	return &UsageApi{
		apiServerCfg: apiServerCfg,
		kustoClient:  kustoClient,
		telem:        telem,
	}
}

func getProjectionVersion(projectionOptions *proto.ProjectionOptions) versioning.Version {
	if projectionOptions == nil {
		return versioning.ActiveProjectionVersion_Api
	}
	return versioning.Version(projectionOptions.VersionOverride)
}

func getRequestType(requestType *proto.RequestType) proto.RequestType {
	if requestType == nil {
		return proto.RequestType_REQUEST_TYPE_USAGE
	}
	return *requestType
}

func getMetrics[TItem any](
	u *UsageApi,
	ctx context.Context,
	getProjection common.GetProjectionFunc,
	requestOptions *proto.RequestOptions) (*GetItemsResult[TItem], error) {

	err := validateRequest(requestOptions)
	if err != nil {
		return nil, err
	}

	setMetricsRequestDefaults(requestOptions)

	version := getProjectionVersion(requestOptions.ProjectionOptions)
	projection := getProjection(version, requestOptions.Scope)

	getTotalCount := true
	getDelayTimes := true

	secondaryOrderBy := getDefaultOrderBy(requestOptions)

	getItemsResult, err := getItems[TItem](ctx, u.telem, u.apiServerCfg.Kusto, u.kustoClient, projection, getTotalCount, getDelayTimes, requestOptions, secondaryOrderBy)
	if err != nil {
		return nil, err
	}

	return getItemsResult, nil
}

func getItems[TItem any](
	ctx context.Context,
	telem *telemetry.Telemetry,
	kustoCfg config.KustoConfig,
	kustoClient *kusto.Client,
	projection common.ProjectionInfo,
	getTotalCount bool,
	getDelayTimes bool,
	reqOptions *proto.RequestOptions,
	secondaryOrderBy *proto.OrderBy) (*GetItemsResult[TItem], error) {
	ctx, span := telemetry.Trace(ctx, "api.getItems")
	defer span.End()

	projection.KustoQuery() // call this here to fix some issues with filtering in summary projections (it removes some unsupported filters)

	queryOptions, err := convertQueryOptionsFromRequestOptions(reqOptions, secondaryOrderBy, kustoCfg)
	if err != nil {
		return nil, err
	}

	aggInterval, err := getKustoAggregationIntervalFromDateRange(*reqOptions.DateRange)
	if err != nil {
		return nil, err
	}

	reader, err := common.NewKustoReader[TItem](kustoClient, projection, aggInterval, telem)
	if err != nil {
		return nil, fmt.Errorf("failed to create kusto reader: %w", err)
	}

	// Set the end time to the current time if not previous month
	// If we get the delay times, we will set the end time to the current time minus the total delay
	now := RealClock{}.Now().UTC()
	timeRange := TimeRange{StartTime: *timestamppb.New(*queryOptions.StartDay), EndTime: *timestamppb.New(now)}
	if *reqOptions.DateRange == proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH {
		timeRange.EndTime = *timestamppb.New(time.Date(now.Year(), now.Month(), 0 /* 0 means last day of prev month */, 0, 0, 0, 0, now.Location()))
	}

	if *reqOptions.DateRange == proto.DateRangeType_DATE_RANGE_TYPE_CUSTOM && !customDateRangeNeedsDelayTime(reqOptions.GetCustomDateRange().GetEnd().AsTime()) {
		timeRange.EndTime = *timestamppb.New(utils.GetStartOfDay(reqOptions.GetCustomDateRange().GetEnd().AsTime()))
	}

	// Get the query results and the kusto delay times in parallel
	var result *common.QueryResult[TItem]
	var delayTimes common.KustoDelayTimes = common.KustoDelayTimes{}
	g, ctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		var err error
		result, err = reader.QueryUsageItems(ctx, *queryOptions, getTotalCount)
		if err != nil {
			return fmt.Errorf("failed to query usage items: %w", err)
		}
		return nil
	})

	// The previous month date range will not have delay times
	if getDelayTimes && delayTimeNeeded(reqOptions) {
		g.Go(func() error {
			var err error
			delayTimes, err = reader.QueryKustoDelayTimes(ctx)
			if err != nil {
				return fmt.Errorf("failed to query kusto delays: %w", err)
			}
			// Set the end time to the current time minus the total delay if not previous month
			endTime := now.Add(-delayTimes.TotalDelay)
			timeRange.EndTime = *timestamppb.New(endTime)
			return nil
		})
	}

	if err := g.Wait(); err != nil {
		return nil, err
	}

	return &GetItemsResult[TItem]{Items: result.Items, TotalItems: result.TotalItems, DelayTimes: delayTimes, TimeRange: timeRange}, nil
}

func delayTimeNeeded(reqOptions *proto.RequestOptions) bool {
	if *reqOptions.DateRange == proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH {
		return false
	}

	if *reqOptions.DateRange == proto.DateRangeType_DATE_RANGE_TYPE_CUSTOM {
		return customDateRangeNeedsDelayTime(reqOptions.GetCustomDateRange().GetEnd().AsTime())
	}

	return true
}

func getKustoAggregationIntervalFromDateRange(dateRange proto.DateRangeType) (common.ProjectionAggregationInterval, error) {
	var aggInterval common.ProjectionAggregationInterval
	switch dateRange {
	case proto.DateRangeType_DATE_RANGE_TYPE_LATEST_MONTH, proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH, proto.DateRangeType_DATE_RANGE_TYPE_LAST_YEAR:
		aggInterval = common.ProjectionAggregationIntervalMonthly
	case proto.DateRangeType_DATE_RANGE_TYPE_CURRENT_WEEK:
		aggInterval = common.ProjectionAggregationIntervalDaily // this was changed to daily to delete weekly projections
	case proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS, proto.DateRangeType_DATE_RANGE_TYPE_LAST_90_DAYS, proto.DateRangeType_DATE_RANGE_TYPE_CUSTOM:
		// We use the daily MVs for the last 30 and 90 days, until we implement smarter query logic
		aggInterval = common.ProjectionAggregationIntervalDaily
	default:
		return aggInterval, fmt.Errorf("invalid date range: %v", dateRange)
	}

	return aggInterval, nil
}

func setMetricsRequestDefaults(options *proto.RequestOptions) {
	if options != nil {
		if options.OrderBy == nil {
			options.OrderBy = getDefaultOrderBy(options)
		}

		setDefaultLimits(options)

	}
}

func setSearchRequestDefaults(options *proto.RequestOptions) {
	if options != nil {
		if options.DateRange == nil {
			defaultDateRange := proto.DateRangeType_DATE_RANGE_TYPE_LAST_YEAR
			options.DateRange = &defaultDateRange
		}

		if options.Search == nil {
			defaultSearchTerm := ""
			options.Search = &defaultSearchTerm
		}

		setDefaultLimits(options)
	}
}

func setDefaultLimits(options *proto.RequestOptions) {
	if options != nil {
		if options.Limit == nil {
			defaultLimit := uint64(1000)
			options.Limit = &defaultLimit
		}

		if options.Offset == nil {
			defaultOffset := uint64(0)
			options.Offset = &defaultOffset
		}
	}
}

func getDefaultOrderBy(options *proto.RequestOptions) *proto.OrderBy {
	if options.RequestType != nil {
		requestType := *options.RequestType
		if requestType == proto.RequestType_REQUEST_TYPE_PERFORMANCE {
			return &PerformanceDefaultOrderBy
		}
	}

	// default to Usage when request type not set because it came first
	return &UsageDefaultOrderBy
}

func setRequestType(options *proto.RequestOptions, defaultRequestType proto.RequestType) {
	if options != nil {
		if options.RequestType == nil {
			options.RequestType = &defaultRequestType
		}
	}
}

// validate request options is not nil and scope is correct
func validateRequest(options *proto.RequestOptions) error {
	if options != nil {
		err := validateScope(options.Scope)
		if err != nil {
			return err
		}

		err = validateCustomDateRange(options)
		return err
	}

	return twirp.RequiredArgumentError("RequestOptions")
}

func validateScope(scope *proto.Scope) error {
	if scope != nil && scope.GetScopeType() != proto.ScopeType_SCOPE_TYPE_UNKNOWN {
		if scope.GetScopeType() == proto.ScopeType_SCOPE_TYPE_REPO && scope.RepositoryId != nil && scope.OwnerId != nil {
			// repo scope requires both repo and owner id
			return nil
		}

		if scope.GetScopeType() == proto.ScopeType_SCOPE_TYPE_ORG && scope.OwnerId != nil {
			// org scope requires owner id
			return nil
		}

		if scope.GetScopeType() == proto.ScopeType_SCOPE_TYPE_ENTERPRISE && scope.EnterpriseOrgs != nil && len(scope.GetEnterpriseOrgs()) > 0 {
			// enterprise scope requires list of enterprise orgs
			return nil
		}

		return fmt.Errorf("Invalid scope provided in request options")
	}

	return twirp.RequiredArgumentError("Scope")
}

func validateSummary(options *proto.RequestOptions) error {
	err := validateRequest(options)
	if err != nil {
		return err
	}

	if options.DateRange == nil {
		return twirp.RequiredArgumentError("DateRange")
	}

	return nil
}

func validateCustomDateRange(options *proto.RequestOptions) error {
	if options.GetDateRange() != proto.DateRangeType_DATE_RANGE_TYPE_CUSTOM {
		return nil
	}

	if options.GetCustomDateRange() == nil {
		return twirp.RequiredArgumentError("CustomDateRange")
	}

	start := options.GetCustomDateRange().GetStart()
	end := options.GetCustomDateRange().GetEnd()

	if start == nil || end == nil {
		return twirp.RequiredArgumentError("CustomDateRange.Start and CustomDateRange.End are both required")
	}

	startTime := utils.GetStartOfDay(start.AsTime())
	endTime := utils.GetStartOfDay(end.AsTime())

	if startTime.Compare(endTime) > 0 {
		// start is after end
		return twirp.InvalidArgumentError("CustomDateRange", "Start must come before End")
	}

	endTimeMax := startTime.AddDate(0, 0, 100) // max is start + 100 days

	if endTime.Compare(endTimeMax) > 0 {
		// end time falls outside range
		return twirp.InvalidArgumentError("CustomDateRange", "Max 100 days between Start and End, current range is too large")
	}

	return nil

}

func customDateRangeNeedsDelayTime(end time.Time) bool {
	yesterday := utils.GetStartOfDay(time.Now()).AddDate(0, 0, -1)

	if utils.GetStartOfDay(end).Compare(yesterday) > 0 {
		return true // calculate delay time if end time is greater than yesterday
	}

	return false
}
