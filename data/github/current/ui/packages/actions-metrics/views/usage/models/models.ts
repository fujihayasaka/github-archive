import type {ApproximateNumber, Repository, MetricsRunnerItem, Organization} from '../../../common/models/models'

// These should match https://github.com/github/actions-usage-metrics/blob/main/proto/usage.proto
// as (aside from repository info) we currently pass them through directly from the AUM backend.

export interface UsageWorkflowMetricsItem extends UsageMetricsItem {
  org?: Organization
  repository?: Repository
  workflowFilePath?: string
  workflowExecutions?: ApproximateNumber
  jobs?: ApproximateNumber
}

export interface UsageJobMetricsItem extends UsageMetricsItem {
  org?: Organization
  repository?: Repository
  workflowFilePath?: string
  jobName?: string
  jobExecutions?: number
  runnerLabels?: string
}

export interface UsageOrgMetricsItem extends UsageMetricsItem {
  org?: Organization
  workflowExecutions?: ApproximateNumber
  workflows?: ApproximateNumber
}

export interface UsageRepositoryMetricsItem extends UsageMetricsItem {
  org?: Organization
  repository?: Repository
  workflowExecutions?: ApproximateNumber
  workflows?: ApproximateNumber
}

export interface UsageRuntimeMetricsItem extends Omit<UsageMetricsItem, 'runnerType'> {
  workflowExecutions?: ApproximateNumber
  workflows?: ApproximateNumber
}

export interface UsageRunnerMetricsItem extends Omit<UsageMetricsItem, 'runnerRuntime'> {
  workflowExecutions?: ApproximateNumber
  workflows?: ApproximateNumber
}

interface UsageMetricsItem extends MetricsRunnerItem {
  totalMinutes?: number
}

export interface AnyUsageItem
  extends UsageWorkflowMetricsItem,
    UsageJobMetricsItem,
    UsageRepositoryMetricsItem,
    UsageRunnerMetricsItem,
    UsageRuntimeMetricsItem {}
