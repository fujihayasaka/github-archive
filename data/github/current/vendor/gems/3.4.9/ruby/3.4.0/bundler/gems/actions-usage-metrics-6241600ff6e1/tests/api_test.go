package tests

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/utils"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	"github.com/stretchr/testify/assert"
)

func TestWorkflowUsage(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config
	repoId := int64(3)  // github/github

	testCases := getRequestOptionsForMetricsTestCases(ownerId, repoId, false)

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-workflow-usage-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetUsageByRepoWorkflowRunnerRequest{
				RequestOptions: testCase,
			}

			response, err := twirpClient.GetUsageByRepoWorkflowRunner(ctx, &request)
			assert.NoError(t, err)
			assert.True(t, len(response.Items) > 0)
			assert.True(t, response.TotalItems > 0)
			assert.True(t, response.Items[0].GetOwnerId() > 0)
			assert.True(t, response.Items[0].GetRepositoryId() > 0)
			assert.True(t, response.Items[0].GetTotalMinutes() > 0)
			assert.True(t, response.Items[0].GetJobs().GetCount() > 0)
			assert.True(t, response.Items[0].GetWorkflowExecutions().GetCount() > 0)
			assert.True(t, response.Items[0].GetRunnerRuntime().Number() > 0)
			assert.True(t, response.Items[0].GetRunnerType().Number() > 0)
			assert.True(t, len(response.Items[0].GetWorkflowFilePath()) > 0)
		})
	}
}

func TestWorkflowUsageErrorCases(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config
	repoId := int64(3)  // github/github

	testCases := getRequestOptionsForErrorResults(ownerId, repoId)

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-workflow-usage-error-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetUsageByRepoWorkflowRunnerRequest{
				RequestOptions: testCase,
			}

			_, err := twirpClient.GetUsageByRepoWorkflowRunner(ctx, &request)
			assert.Error(t, err)
		})
	}
}

func TestRepo(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config
	repoId := int64(3)  // github/github

	testCases := getRequestOptionsForMetricsTestCases(ownerId, repoId, true)

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-repo-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetRepoUsageRequest{
				RequestOptions: testCase,
			}

			response, err := twirpClient.GetRepoUsage(ctx, &request)
			assert.NoError(t, err)
			assert.True(t, len(response.Items) > 0)
			assert.True(t, response.TotalItems > 0)
			assert.True(t, response.Items[0].GetOwnerId() > 0)
			assert.True(t, response.Items[0].GetRepositoryId() > 0)
			assert.True(t, response.Items[0].GetTotalMinutes() > 0)
			assert.True(t, response.Items[0].GetJobExecutions() > 0)
			assert.True(t, response.Items[0].GetWorkflowExecutions().GetCount() > 0)
			assert.True(t, response.Items[0].GetAverageQueueTime() > 0)
			assert.True(t, response.Items[0].GetAverageRunTime() > 0)
			assert.True(t, response.Items[0].GetWorkflows().GetCount() > 0)
		})
	}
}

func TestOrg(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config

	testCases := getRequestOptionsForMetricsTestCasesEnterpriseOnly(ownerId, true)

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-org-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetOrgUsageRequest{
				RequestOptions: testCase,
			}

			response, err := twirpClient.GetOrgUsage(ctx, &request)
			assert.NoError(t, err)
			assert.True(t, len(response.Items) > 0)
			assert.True(t, response.TotalItems > 0)
			assert.True(t, response.Items[0].GetOwnerId() > 0)
			assert.True(t, response.Items[0].GetTotalMinutes() > 0)
			assert.True(t, response.Items[0].GetJobExecutions() > 0)
			assert.True(t, response.Items[0].GetWorkflowExecutions().GetCount() > 0)
			assert.True(t, response.Items[0].GetAverageQueueTime() > 0)
			assert.True(t, response.Items[0].GetAverageRunTime() > 0)
			assert.True(t, response.Items[0].GetWorkflows().GetCount() > 0)
		})
	}
}

func TestJob(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config
	repoId := int64(3)  // github/github

	testCases := getRequestOptionsForMetricsTestCases(ownerId, repoId, true)

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-job-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetJobUsageRequest{
				RequestOptions: testCase,
			}

			response, err := twirpClient.GetJobUsage(ctx, &request)
			assert.NoError(t, err)
			assert.True(t, len(response.Items) > 0)
			assert.True(t, response.TotalItems > 0)
			assert.True(t, response.Items[0].GetOwnerId() > 0)
			assert.True(t, response.Items[0].GetRepositoryId() > 0)
			assert.True(t, response.Items[0].GetTotalMinutes() > 0)
			assert.True(t, response.Items[0].GetJobExecutions() > 0)
			assert.True(t, response.Items[0].GetAverageQueueTime() > 0)
			assert.True(t, response.Items[0].GetAverageRunTime() > 0)
			assert.True(t, len(response.Items[0].GetJobName()) > 0)
			assert.True(t, response.Items[0].GetRunnerType().Number() > 0)
		})
	}
}

func TestRuntime(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config
	repoId := int64(3)  // github/github

	testCases := getRequestOptionsForMetricsTestCases(ownerId, repoId, true)

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-runtime-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetRunnerRuntimeUsageRequest{
				RequestOptions: testCase,
			}

			response, err := twirpClient.GetRunnerRuntimeUsage(ctx, &request)
			assert.NoError(t, err)

			i := 0
			if len(response.Items) > 1 && response.Items[i].GetRunnerRuntime().Number() == 0 {
				// there is some unknown data, so check next item for tests
				i = 1
			}

			assert.True(t, len(response.Items) > 0)
			assert.True(t, response.TotalItems > 0)
			assert.True(t, response.Items[i].GetTotalMinutes() > 0)
			assert.True(t, response.Items[i].GetJobExecutions() > 0)
			assert.True(t, response.Items[i].GetAverageQueueTime() > 0)
			assert.True(t, response.Items[i].GetAverageRunTime() > 0)
			assert.True(t, response.Items[i].GetWorkflowExecutions().GetCount() > 0)
			assert.True(t, response.Items[i].GetRunnerRuntime().Number() > 0)
		})
	}
}

func TestRunnerType(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config
	repoId := int64(3)  // github/github

	testCases := getRequestOptionsForMetricsTestCases(ownerId, repoId, true)

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-runnertype-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetRunnerTypeUsageRequest{
				RequestOptions: testCase,
			}

			response, err := twirpClient.GetRunnerTypeUsage(ctx, &request)
			assert.NoError(t, err)

			i := 0
			if len(response.Items) > 1 && response.Items[i].GetRunnerType().Number() == 0 {
				// there is some unknown data, so check next item for tests
				i = 1
			}

			assert.True(t, len(response.Items) > 0)
			assert.True(t, response.TotalItems > 0)
			assert.True(t, response.Items[i].GetTotalMinutes() > 0)
			assert.True(t, response.Items[i].GetJobExecutions() > 0)
			assert.True(t, response.Items[i].GetAverageQueueTime() > 0)
			assert.True(t, response.Items[i].GetAverageRunTime() > 0)
			assert.True(t, response.Items[i].GetWorkflowExecutions().GetCount() > 0)
			assert.True(t, response.Items[i].GetRunnerType().Number() > 0)
		})
	}
}

func TestWorkflowPerformance(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config
	repoId := int64(3)  // github/github

	testCases := getRequestOptionsForMetricsTestCases(ownerId, repoId, false)

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-workflow-performance-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetWorkflowPerformanceRequest{
				RequestOptions: testCase,
			}

			response, err := twirpClient.GetWorkflowPerformance(ctx, &request)
			assert.NoError(t, err)
			assert.True(t, len(response.Items) > 0)
			assert.True(t, response.TotalItems > 0)
			assert.True(t, response.Items[0].GetOwnerId() > 0)
			assert.True(t, response.Items[0].GetAverageRunTime() > 0)
			assert.True(t, response.Items[0].GetWorkflowExecutions() > 0)
			assert.True(t, response.Items[0].GetRepositoryId() > 0)
			assert.True(t, len(response.Items[0].GetWorkflowFilePath()) > 0)
			assert.True(t, response.Items[0].Jobs.GetCount() > 0)
		})
	}
}

func TestUsageSummary(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config
	repoId := int64(3)  // github/github

	testCases := getSummaryTestCases(ownerId, repoId)

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-usage-summary-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetUsageSummaryRequest{
				RequestOptions: testCase.options,
				MetricsType:    testCase.metricsType,
			}

			response, err := twirpClient.GetUsageSummary(ctx, &request)
			assert.NoError(t, err)
			assert.True(t, response.GetTotalMinutes() > 0)
			assert.True(t, response.GetJobExecutions() > 0)
		})
	}
}

func TestPerformanceSummary(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config
	repoId := int64(3)  // github/github

	testCases := getSummaryTestCases(ownerId, repoId)

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-performance-summary-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetPerformanceSummaryRequest{
				RequestOptions: testCase.options,
				MetricsType:    testCase.metricsType,
			}

			response, err := twirpClient.GetPerformanceSummary(ctx, &request)
			assert.NoError(t, err)
			assert.True(t, response.GetAverageJobQueueTime() > 0)
			assert.True(t, response.GetAverageJobRunTime() > 0)
			assert.True(t, response.GetTotalFailureMinutes() > 0)
		})
	}
}

func TestAutoCompleteJobs(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config
	repoId := int64(3)  // github/github
	search := "gold"

	testCases := []*proto.RequestOptions{
		{
			Scope: utils.GetScopeFromOwnerId(ownerId),
		},
		{
			Scope: utils.GetScopeFromRepo(ownerId, repoId),
		},
		{
			Scope:  utils.GetScopeFromOwnerId(ownerId),
			Search: &search,
		},
		{
			Scope:  utils.GetScopeFromRepo(ownerId, repoId),
			Search: &search,
		},
	}

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-auto-complete-jobs-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetJobsRequest{
				RequestOptions: testCase,
			}

			response, err := twirpClient.GetJobs(ctx, &request)
			assert.NoError(t, err)
			assert.True(t, len(response.GetJobs()) > 0)

			// if there was a search string make sure it is in every result
			if testCase.Search != nil {
				for _, val := range response.GetJobs() {
					lowerStr := strings.ToLower(val.JobName)
					assert.True(t, strings.Contains(lowerStr, search))
				}
			}
		})
	}
}

func TestAutoCompleteWorkflows(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config
	repoId := int64(3)  // github/github
	search := "ci"

	testCases := []*proto.RequestOptions{
		{
			Scope: utils.GetScopeFromOwnerId(ownerId),
		},
		{
			Scope: utils.GetScopeFromRepo(ownerId, repoId),
		},
		{
			Scope:  utils.GetScopeFromOwnerId(ownerId),
			Search: &search,
		},
		{
			Scope:  utils.GetScopeFromRepo(ownerId, repoId),
			Search: &search,
		},
	}

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-auto-complete-workflows-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetWorkflowsRequest{
				RequestOptions: testCase,
			}

			response, err := twirpClient.GetWorkflows(ctx, &request)
			assert.NoError(t, err)
			assert.True(t, len(response.GetWorkflows()) > 0)

			// if there was a search string make sure it is in every result
			if testCase.Search != nil {
				for _, val := range response.GetWorkflows() {
					lowerStr := strings.ToLower(val.FileName)
					assert.True(t, strings.Contains(lowerStr, search))
				}
			}
		})
	}
}

func TestAutoCompleteRunnerLabels(t *testing.T) {
	twirpClient := GetTwirpClient(t)
	ctx := context.Background()
	ownerId := int64(1) // maps to GitHub 9919 through dev config
	repoId := int64(3)  // github/github
	search := "ubuntu"

	testCases := []*proto.RequestOptions{
		{
			Scope: utils.GetScopeFromOwnerId(ownerId),
		},
		{
			Scope: utils.GetScopeFromRepo(ownerId, repoId),
		},
		{
			Scope:  utils.GetScopeFromOwnerId(ownerId),
			Search: &search,
		},
		{
			Scope:  utils.GetScopeFromRepo(ownerId, repoId),
			Search: &search,
		},
	}

	for index, testCase := range testCases {

		t.Run(fmt.Sprintf("api-auto-complete-jobs-test-%d", index), func(t *testing.T) {
			t.Parallel() // Run these tests in parallel

			request := proto.GetRunnerLabelsRequest{
				RequestOptions: testCase,
			}

			response, err := twirpClient.GetRunnerLabels(ctx, &request)
			assert.NoError(t, err)
			assert.True(t, len(response.GetRunnerLabels()) > 0)

			// if there was a search string make sure it is in every result
			if testCase.Search != nil {
				for _, val := range response.GetRunnerLabels() {
					lowerStr := strings.ToLower(val.RunnerLabel)
					assert.True(t, strings.Contains(lowerStr, search))
				}
			}
		})
	}
}

func getRequestOptionsForErrorResults(ownerId int64, repoId int64) []*proto.RequestOptions {
	enterpriseId := int64(1)

	return []*proto.RequestOptions{
		nil,
		{
			// missing scope
			Scope:     nil,
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_CURRENT_WEEK.Enum(),
		},
		{
			// repo level without org and repo id
			Scope: &proto.Scope{
				ScopeType: proto.ScopeType_SCOPE_TYPE_REPO,
			},
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS.Enum(),
		},
		{
			// enterprise level without list of org ids
			Scope: &proto.Scope{
				ScopeType:    proto.ScopeType_SCOPE_TYPE_ENTERPRISE,
				EnterpriseId: &enterpriseId,
			},
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS.Enum(),
		},
		{
			// org level without org id
			Scope: &proto.Scope{
				ScopeType: proto.ScopeType_SCOPE_TYPE_ORG,
			},
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS.Enum(),
		},
		{
			// repo level with org id but no repo id
			Scope: &proto.Scope{
				ScopeType: proto.ScopeType_SCOPE_TYPE_REPO,
				OwnerId:   &ownerId,
			},
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS.Enum(),
		},
		{
			// repo level with repo id but no org id
			Scope: &proto.Scope{
				ScopeType:    proto.ScopeType_SCOPE_TYPE_REPO,
				RepositoryId: &repoId,
			},
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS.Enum(),
		},
		{
			// org level with repo id instead of org id
			Scope: &proto.Scope{
				ScopeType:    proto.ScopeType_SCOPE_TYPE_ORG,
				RepositoryId: &ownerId,
			},
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS.Enum(),
		},
		{
			// enterprise level with single owner id instead of list of org ids
			Scope: &proto.Scope{
				ScopeType:    proto.ScopeType_SCOPE_TYPE_ENTERPRISE,
				OwnerId:      &ownerId,
				EnterpriseId: &enterpriseId,
			},
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS.Enum(),
		},
		{
			// enterprise level without hash
			Scope: &proto.Scope{
				ScopeType:      proto.ScopeType_SCOPE_TYPE_ENTERPRISE,
				EnterpriseOrgs: []int64{9919, 33435682},
				EnterpriseId:   &enterpriseId,
			},
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS.Enum(),
		},
	}
}

func getRequestOptionsForMetricsTestCases(ownerId int64, repoId int64, alternateUsageAndPerf bool) []*proto.RequestOptions {
	var requestTypeAlternate *proto.RequestType = nil

	if alternateUsageAndPerf {
		requestTypeAlternate = proto.RequestType_REQUEST_TYPE_PERFORMANCE.Enum()
	}

	return []*proto.RequestOptions{
		// alternate org and repo scoped
		{
			Scope:       utils.GetScopeFromOwnerId(ownerId),
			DateRange:   proto.DateRangeType_DATE_RANGE_TYPE_CURRENT_WEEK.Enum(),
			RequestType: requestTypeAlternate,
		},
		{
			Scope:       utils.GetScopeFromRepo(ownerId, repoId),
			DateRange:   proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS.Enum(),
			RequestType: requestTypeAlternate,
		},
		{
			Scope:     utils.GetScopeFromOwnerId(ownerId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_90_DAYS.Enum(),
		},
		{
			Scope:     utils.GetScopeFromRepo(ownerId, repoId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LATEST_MONTH.Enum(),
		},
		{
			Scope:     utils.GetScopeFromOwnerId(ownerId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH.Enum(),
		},
		{
			Scope:     utils.GetScopeFromRepo(ownerId, repoId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_YEAR.Enum(),
		},
		{
			Scope:     utils.GetScopeFromEnterpriseOrgs([]int64{ownerId, 33435682}), //ownerId + bbq-beets
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH.Enum(),
		},
	}
}

func getRequestOptionsForMetricsTestCasesEnterpriseOnly(ownerId int64, alternateUsageAndPerf bool) []*proto.RequestOptions {
	var requestTypeAlternate *proto.RequestType = nil

	if alternateUsageAndPerf {
		requestTypeAlternate = proto.RequestType_REQUEST_TYPE_PERFORMANCE.Enum()
	}

	return []*proto.RequestOptions{
		// alternate org and repo scoped
		{
			Scope:       utils.GetScopeFromEnterpriseOrgs([]int64{ownerId, 33435682}), //ownerId + bbq-beets
			DateRange:   proto.DateRangeType_DATE_RANGE_TYPE_CURRENT_WEEK.Enum(),
			RequestType: requestTypeAlternate,
		},
		{
			Scope:       utils.GetScopeFromEnterpriseOrgs([]int64{ownerId, 33435682}), //ownerId + bbq-beets
			DateRange:   proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS.Enum(),
			RequestType: requestTypeAlternate,
		},
		{
			Scope:     utils.GetScopeFromEnterpriseOrgs([]int64{ownerId, 33435682}), //ownerId + bbq-beets
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_90_DAYS.Enum(),
		},
		{
			Scope:     utils.GetScopeFromEnterpriseOrgs([]int64{ownerId, 33435682}), //ownerId + bbq-beets
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LATEST_MONTH.Enum(),
		},
		{
			Scope:     utils.GetScopeFromEnterpriseOrgs([]int64{ownerId, 33435682}), //ownerId + bbq-beets
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH.Enum(),
		},
		{
			Scope:     utils.GetScopeFromEnterpriseOrgs([]int64{ownerId, 33435682}), //ownerId + bbq-beets
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_YEAR.Enum(),
		},
		{
			Scope:       utils.GetScopeFromEnterpriseOrgs([]int64{ownerId, 33435682}), //ownerId + bbq-beets
			DateRange:   proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH.Enum(),
			RequestType: requestTypeAlternate,
		},
	}
}

type summaryTestCase struct {
	options     *proto.RequestOptions
	metricsType *proto.MetricsType
}

func getSummaryTestCases(ownerId int64, repoId int64) []*summaryTestCase {
	return []*summaryTestCase{
		{options: &proto.RequestOptions{
			// this test case will fail if tried around start of week (12 AM UTC Monday)
			Scope:     utils.GetScopeFromOwnerId(ownerId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_CURRENT_WEEK.Enum(),
		},
			metricsType: proto.MetricsType_METRICS_TYPE_JOB.Enum(),
		},
		{options: &proto.RequestOptions{
			Scope:     utils.GetScopeFromRepo(ownerId, repoId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_30_DAYS.Enum(),
		},
			metricsType: proto.MetricsType_METRICS_TYPE_REPO.Enum(),
		},
		{options: &proto.RequestOptions{
			Scope:     utils.GetScopeFromOwnerId(ownerId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_90_DAYS.Enum(),
		},
			metricsType: proto.MetricsType_METRICS_TYPE_RUNNER_RUNTIME.Enum(),
		},
		{options: &proto.RequestOptions{
			Scope:     utils.GetScopeFromRepo(ownerId, repoId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LATEST_MONTH.Enum(),
		},
			metricsType: proto.MetricsType_METRICS_TYPE_RUNNER_TYPE.Enum(),
		},
		{options: &proto.RequestOptions{
			Scope:     utils.GetScopeFromOwnerId(ownerId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH.Enum(),
		},
			metricsType: proto.MetricsType_METRICS_TYPE_WORKFLOW.Enum(),
		},
		{options: &proto.RequestOptions{
			Scope:     utils.GetScopeFromRepo(ownerId, repoId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_LAST_YEAR.Enum(),
		},
		},
		{options: &proto.RequestOptions{
			Scope:     utils.GetScopeFromRepo(ownerId, repoId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH.Enum(),
			Filters: []*proto.Filter{
				{
					Key:      string(common.RepositoryIdFilterKey),
					Operator: proto.FilterOperator_FILTER_OPERATOR_EQUALS,
					Values:   []string{"3"}, // github/github repo
				},
			},
		},
			metricsType: proto.MetricsType_METRICS_TYPE_JOB.Enum(),
		},
		{options: &proto.RequestOptions{
			Scope:     utils.GetScopeFromRepo(ownerId, repoId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH.Enum(),
			Filters: []*proto.Filter{
				{
					Key:      string(common.RepositoryIdFilterKey),
					Operator: proto.FilterOperator_FILTER_OPERATOR_EQUALS,
					Values:   []string{"3"}, // github/github repo
				},
			},
		},
			metricsType: proto.MetricsType_METRICS_TYPE_REPO.Enum(),
		},
		{options: &proto.RequestOptions{
			Scope:     utils.GetScopeFromRepo(ownerId, repoId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH.Enum(),
			Filters: []*proto.Filter{
				{
					Key:      string(common.RepositoryIdFilterKey),
					Operator: proto.FilterOperator_FILTER_OPERATOR_EQUALS,
					Values:   []string{"3"}, // github/github repo
				},
			},
		},
			metricsType: proto.MetricsType_METRICS_TYPE_WORKFLOW.Enum(),
		},
		{options: &proto.RequestOptions{
			Scope:     utils.GetScopeFromRepo(ownerId, repoId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH.Enum(),
			Filters: []*proto.Filter{
				{
					Key:      string(common.RunnerTypeFilterKey),
					Operator: proto.FilterOperator_FILTER_OPERATOR_EQUALS,
					Values:   []string{proto.RunnerType_RUNNER_TYPE_HOSTED.String()}, // github/github repo
				},
			},
		},
			metricsType: proto.MetricsType_METRICS_TYPE_RUNNER_TYPE.Enum(),
		},
		{options: &proto.RequestOptions{
			Scope:     utils.GetScopeFromRepo(ownerId, repoId),
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH.Enum(),
			Filters: []*proto.Filter{
				{
					Key:      string(common.RunnerRuntimeFilterKey),
					Operator: proto.FilterOperator_FILTER_OPERATOR_EQUALS,
					Values:   []string{proto.RunnerRuntime_RUNNER_RUNTIME_LINUX.String()}, // github/github repo
				},
			},
		},
			metricsType: proto.MetricsType_METRICS_TYPE_RUNNER_RUNTIME.Enum(),
		},
		{options: &proto.RequestOptions{
			Scope:     utils.GetScopeFromEnterpriseOrgs([]int64{ownerId, 33435682}), //ownerId + bbq-beets
			DateRange: proto.DateRangeType_DATE_RANGE_TYPE_PREVIOUS_MONTH.Enum(),
			Filters: []*proto.Filter{
				{
					Key:      string(common.WorkflowExecutionsFilterKey),
					Operator: proto.FilterOperator_FILTER_OPERATOR_GREATER_THAN,
					Values:   []string{"1"},
				},
			},
		},
			metricsType: proto.MetricsType_METRICS_TYPE_WORKFLOW.Enum(),
		},
	}
}
