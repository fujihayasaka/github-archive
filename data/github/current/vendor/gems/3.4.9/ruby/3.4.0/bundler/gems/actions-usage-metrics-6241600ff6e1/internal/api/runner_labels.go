package api

import (
	"context"

	"github.com/github/actions-usage-metrics/internal/querybuilder"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

// GetRunnerLabels is used to satisfy autocomplete requests for workflow file paths.
func (u *UsageApi) GetRunnerLabels(ctx context.Context, req *proto.GetRunnerLabelsRequest) (*proto.GetRunnerLabelsResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetRunnerLabels")
	defer span.End()

	options := req.RequestOptions
	searchField := querybuilder.RunnerLabelsAutoCompleteFieldName.String()
	options.SearchField = &searchField

	options.SearchField = &searchField

	autoCompleteRequest := proto.GetAutoCompleteRequest{
		RequestOptions: options,
	}
	result, err := u.getAutoComplete(ctx, &autoCompleteRequest)
	if err != nil {
		return nil, err
	}

	return &proto.GetRunnerLabelsResponse{RunnerLabels: convertLabelsToProtoFromItems(result.Items)}, nil
}

func convertLabelsToProtoFromItems(items []string) []*proto.RunnerLabel {
	labels := make([]*proto.RunnerLabel, 0, len(items))
	for _, item := range items {
		labels = append(labels, &proto.RunnerLabel{
			RunnerLabel: item,
		})
	}
	return labels
}
