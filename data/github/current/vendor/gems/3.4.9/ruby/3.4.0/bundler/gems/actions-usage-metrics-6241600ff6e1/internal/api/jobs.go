package api

import (
	"context"

	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

// GetJobs is used to satisfy autocomplete requests for workflow file paths.
func (u *UsageApi) GetJobs(ctx context.Context, req *proto.GetJobsRequest) (*proto.GetJobsResponse, error) {
	ctx, span := telemetry.Trace(ctx, "UsageApi.GetJobs")
	defer span.End()

	options := req.RequestOptions
	searchField := "jobName"
	options.SearchField = &searchField

	options.SearchField = &searchField

	autoCompleteRequest := proto.GetAutoCompleteRequest{
		RequestOptions: options,
	}
	result, err := u.getAutoComplete(ctx, &autoCompleteRequest)
	if err != nil {
		return nil, err
	}

	return &proto.GetJobsResponse{Jobs: convertJobsToProtoFromItems(result.Items)}, nil
}

func convertJobsToProtoFromItems(items []string) []*proto.Job {
	jobs := make([]*proto.Job, 0, len(items))
	for _, item := range items {
		jobs = append(jobs, &proto.Job{
			JobName: item,
		})
	}
	return jobs
}
