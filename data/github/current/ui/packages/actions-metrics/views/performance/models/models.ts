import type {Repository, MetricsRunnerItem, ApproximateNumber, Organization} from '../../../common/models/models'

// These should match https://github.com/github/actions-usage-metrics/blob/main/proto/usage.proto
// as (aside from repository info) we currently pass them through directly from the AUM backend.

export interface PerformanceWorkflowMetricsItem
  extends Omit<PerformanceMetricsItem, 'runnerType' | 'runnerRuntime' | 'jobExecutions'> {
  repository?: Repository
  org?: Organization
  workflowFilePath?: string
  workflowExecutions?: number
  jobs?: ApproximateNumber
}

export interface PerformanceJobMetricsItem extends PerformanceMetricsItem {
  jobName?: string
  org?: Organization
  repository?: Repository
  workflowFilePath?: string
  runnerLabels?: string
}

export interface PerformanceRepositoryMetricsItem extends PerformanceMetricsItem {
  org?: Organization
  repository?: Repository
}

export interface PerformanceOrgMetricsItem extends PerformanceMetricsItem {
  org?: Organization
  repository?: Repository
}

export interface PerformanceRuntimeMetricsItem extends Omit<PerformanceMetricsItem, 'runnerType'> {}

export interface PerformanceRunnerMetricsItem extends Omit<PerformanceMetricsItem, 'runnerRuntime'> {}

interface PerformanceMetricsItem extends MetricsRunnerItem {
  failureRate?: number
  averageRunTime?: number
  averageQueueTime?: number
  jobExecutions?: number
}

export interface AnyPerformanceItem
  extends PerformanceWorkflowMetricsItem,
    PerformanceJobMetricsItem,
    PerformanceRepositoryMetricsItem,
    PerformanceRunnerMetricsItem,
    PerformanceRuntimeMetricsItem {}
