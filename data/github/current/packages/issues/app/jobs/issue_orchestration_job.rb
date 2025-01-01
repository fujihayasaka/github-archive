# typed: true
# frozen_string_literal: true

class IssueOrchestrationJob < OrchestrationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  queue_as :issue_orchestration

  # Tenant is resolved from repo during orchestration.execute
  # https://github.com/github/github/blob/master/packages/repositories/app/models/orchestration.rb#L295
  exempt_from_tenant_context_requirement
end
