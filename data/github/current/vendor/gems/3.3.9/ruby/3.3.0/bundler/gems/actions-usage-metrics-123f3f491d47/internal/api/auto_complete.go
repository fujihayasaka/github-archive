package api

import (
	"context"
	"fmt"

	"github.com/github/actions-usage-metrics/internal/projections/autocomplete"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/querybuilder"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"
)

func (u *UsageApi) getAutoComplete(ctx context.Context, req *proto.GetAutoCompleteRequest) (*proto.GetAutoCompleteResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetAutoComplete")
	defer span.End()

	logger := log.WithContext(ctx)

	options := req.RequestOptions
	err := validateRequest(options)
	if err != nil {
		return nil, err
	}

	if options == nil || options.SearchField == nil {
		return nil, fmt.Errorf("Required request params not specified")
	}

	setSearchRequestDefaults(options)
	version := getProjectionVersion(options.ProjectionOptions)

	var projection common.ProjectionInfo
	searchField := *options.SearchField

	switch searchField {
	case querybuilder.JobNameFieldName.String():
		projection = autocomplete.JobsProjection(version, options.Scope)
	case querybuilder.WorkflowFileNameFieldName.String():
		projection = autocomplete.WorkflowsProjection(version, options.Scope)
	case querybuilder.RunnerLabelsAutoCompleteFieldName.String():
		projection = autocomplete.RunnerLabelsProjection(version, options.Scope)
	default:
		return nil, fmt.Errorf("Unknown search field")
	}

	result, err := getItems[autocomplete.AutoCompleteItem](ctx, u.telem, u.apiServerCfg.Kusto, u.kustoClient, projection, false, false, options, nil)

	if err != nil {
		logger.WithError(err).Error("failed to query autocomplete projection using kusto")
		return nil, err
	}

	return &proto.GetAutoCompleteResponse{Items: convertAutoCompleteToProto(result.Items)}, nil
}

func convertAutoCompleteToProto(items []autocomplete.AutoCompleteItem) []string {
	result := make([]string, 0, len(items))
	for _, item := range items {
		result = append(result, item.Item)
	}
	return result
}
