package tests

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/utils"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/stretchr/testify/assert"
)

func TestUsageExport(t *testing.T) {
	exportTests := map[proto.ExportType][]*proto.ExportHeader{
		proto.ExportType_EXPORT_TYPE_WORKFLOW_USAGE: {
			{Key: string(common.WorkflowFilePathFilterKey), Display: "Workflow"},
			{Key: string(common.RepositoryIdFilterKey), Display: "Source repository"},
			{Key: string(common.TotalMinutesFilterKey), Display: "Total minutes"},
			{Key: string(common.WorkflowExecutionsFilterKey), Display: "Workflow runs"},
			{Key: string(common.JobsFilterKey), Display: "Jobs"},
			{Key: string(common.RunnerTypeFilterKey), Display: "Runner type"},
			{Key: string(common.RunnerRuntimeFilterKey), Display: "Runtime OS"},
			{Key: string("_internal_column"), Display: "SHOULD NOT SHOW UP"},
		},
		proto.ExportType_EXPORT_TYPE_JOB_USAGE: {
			{Key: string(common.JobNameFilterKey), Display: "Job"},
			{Key: string(common.WorkflowFilePathFilterKey), Display: "Workflow"},
			{Key: string(common.RepositoryIdFilterKey), Display: "Source repository"},
			{Key: string(common.TotalMinutesFilterKey), Display: "Total minutes"},
			{Key: string(common.JobExecutionsFilterKey), Display: "Job runs"},
			{Key: string(common.RunnerTypeFilterKey), Display: "Runner type"},
			{Key: string(common.RunnerRuntimeFilterKey), Display: "Runtime OS"},
			{Key: string("_internal_column"), Display: "SHOULD NOT SHOW UP"},
		},
		proto.ExportType_EXPORT_TYPE_REPO_USAGE: {
			{Key: string(common.RepositoryIdFilterKey), Display: "Source repository"},
			{Key: string(common.TotalMinutesFilterKey), Display: "Total minutes"},
			{Key: string(common.WorkflowExecutionsFilterKey), Display: "Workflow runs"},
			{Key: string(common.WorkflowsFilterKey), Display: "Workflows"},
			{Key: string("_internal_column"), Display: "SHOULD NOT SHOW UP"},
		},
		proto.ExportType_EXPORT_TYPE_RUNNER_RUNTIME_USAGE: {
			{Key: string(common.RunnerRuntimeFilterKey), Display: "Runtime OS"},
			{Key: string(common.TotalMinutesFilterKey), Display: "Total minutes"},
			{Key: string(common.WorkflowExecutionsFilterKey), Display: "Workflow runs"},
			{Key: string(common.WorkflowsFilterKey), Display: "Workflows"},
			{Key: string("_internal_column"), Display: "SHOULD NOT SHOW UP"},
		},
		proto.ExportType_EXPORT_TYPE_RUNNER_TYPE_USAGE: {
			{Key: string(common.RunnerTypeFilterKey), Display: "Runner type"},
			{Key: string(common.TotalMinutesFilterKey), Display: "Total minutes"},
			{Key: string(common.WorkflowExecutionsFilterKey), Display: "Workflow runs"},
			{Key: string(common.WorkflowsFilterKey), Display: "Workflows"},
			{Key: string("_internal_column"), Display: "SHOULD NOT SHOW UP"},
		},
	}

	testExport(t, exportTests)
}

func TestPerformanceExport(t *testing.T) {
	exportTests := map[proto.ExportType][]*proto.ExportHeader{
		proto.ExportType_EXPORT_TYPE_JOB_USAGE: {
			{Key: string(common.JobNameFilterKey), Display: "Job"},
			{Key: string(common.WorkflowFilePathFilterKey), Display: "Workflow"},
			{Key: string(common.RepositoryIdFilterKey), Display: "Source repository"},
			{Key: string(common.FailureRateFilterKey), Display: "Failure rate"},
			{Key: string(common.AverageRunTimeFilterKey), Display: "Avg job run time"},
			{Key: string(common.AverageQueueTimeFilterKey), Display: "Avg job queue time"},
			{Key: string(common.JobExecutionsFilterKey), Display: "Job runs"},
			{Key: string(common.RunnerTypeFilterKey), Display: "Runner type"},
			{Key: string(common.RunnerRuntimeFilterKey), Display: "Runtime OS"},
			{Key: string("_internal_column"), Display: "SHOULD NOT SHOW UP"},
		},
		proto.ExportType_EXPORT_TYPE_REPO_USAGE: {
			{Key: string(common.RepositoryIdFilterKey), Display: "Source repository"},
			{Key: string(common.FailureRateFilterKey), Display: "Failure rate"},
			{Key: string(common.AverageRunTimeFilterKey), Display: "Avg job run time"},
			{Key: string(common.AverageQueueTimeFilterKey), Display: "Avg job queue time"},
			{Key: string(common.JobExecutionsFilterKey), Display: "Job runs"},
			{Key: string("_internal_column"), Display: "SHOULD NOT SHOW UP"},
		},
		proto.ExportType_EXPORT_TYPE_RUNNER_RUNTIME_USAGE: {
			{Key: string(common.RunnerRuntimeFilterKey), Display: "Runtime OS"},
			{Key: string(common.FailureRateFilterKey), Display: "Failure rate"},
			{Key: string(common.AverageRunTimeFilterKey), Display: "Avg job run time"},
			{Key: string(common.AverageQueueTimeFilterKey), Display: "Avg job queue time"},
			{Key: string(common.JobExecutionsFilterKey), Display: "Job runs"},
			{Key: string("_internal_column"), Display: "SHOULD NOT SHOW UP"},
		},
		proto.ExportType_EXPORT_TYPE_RUNNER_TYPE_USAGE: {
			{Key: string(common.RunnerTypeFilterKey), Display: "Runner type"},
			{Key: string(common.FailureRateFilterKey), Display: "Failure rate"},
			{Key: string(common.AverageRunTimeFilterKey), Display: "Avg job run time"},
			{Key: string(common.AverageQueueTimeFilterKey), Display: "Avg job queue time"},
			{Key: string(common.JobExecutionsFilterKey), Display: "Job runs"},
			{Key: string("_internal_column"), Display: "SHOULD NOT SHOW UP"},
		},
		proto.ExportType_EXPORT_TYPE_WORKFLOW_PERFORMANCE: {
			{Key: string(common.WorkflowFilePathFilterKey), Display: "Workflow"},
			{Key: string(common.RepositoryIdFilterKey), Display: "Source repository"},
			{Key: string(common.WorkflowExecutionsFilterKey), Display: "Workflow runs"},
			{Key: string(common.JobsFilterKey), Display: "Jobs"},
			{Key: string(common.AverageRunTimeFilterKey), Display: "Average Run Time"},
			{Key: string(common.FailureRateFilterKey), Display: "Failure Rate"},
			{Key: string("_internal_column"), Display: "SHOULD NOT SHOW UP"},
		},
	}

	testExport(t, exportTests)
}

func testExport(t *testing.T, exportTests map[proto.ExportType][]*proto.ExportHeader) {
	twirpClient := GetTwirpClient(t)
	ownerId := int64(1)

	for exportType, exportHeaders := range exportTests {
		t.Run(exportType.String(), func(t *testing.T) {
			t.Parallel()
			ctx := context.Background()

			// Start export and get the export ID
			startExportResponse, err := twirpClient.StartExport(
				ctx,
				&proto.StartExportRequest{
					RequestOptions: &proto.RequestOptions{
						Scope:     utils.GetScopeFromOwnerId(ownerId),
						DateRange: proto.DateRangeType_DATE_RANGE_TYPE_CURRENT_WEEK.Enum(),
					},
					ExportType: exportType,
					Headers:    exportHeaders,
				})
			assert.NoError(t, err)
			assert.NotEmpty(t, startExportResponse.GetExportId())

			if err == nil {
				// Get export status and wait for the export to be ready
				retries := 10
				var getExportStatusResponse *proto.GetExportStatusResponse
				for i := range retries {
					time.Sleep(5 * time.Second) // sleep for 5 seconds between each test to try to prevent flakiness
					getExportStatusResponse, err = twirpClient.GetExportStatus(
						ctx,
						&proto.GetExportStatusRequest{
							Scope:    utils.GetScopeFromOwnerId(ownerId),
							ExportId: startExportResponse.ExportId,
						},
					)

					if err != nil && i >= retries-1 {
						// only assert no error if last retry to avoid flakiness
						assert.NoError(t, err)
					}

					if err == nil && getExportStatusResponse.GetStatus() != proto.ExportStatus_EXPORT_STATUS_PENDING {
						break
					}
				}

				// Assert that the export is complete
				assert.Equal(t, proto.ExportStatus_EXPORT_STATUS_COMPLETE, getExportStatusResponse.GetStatus())
				assert.NotEmpty(t, getExportStatusResponse.GetDownloadUrl())

				if err == nil && len(getExportStatusResponse.GetDownloadUrl()) > 0 {
					// Download the export file
					downloadResponse, err := http.Get(getExportStatusResponse.GetDownloadUrl())
					if err != nil {
						assert.Fail(t, "Failed to download export file", err)
					}
					assert.Equal(t, http.StatusOK, downloadResponse.StatusCode)
				} else {
					assert.Fail(t, "Failed to get download URL", nil)
				}
			}
		})
	}
}
