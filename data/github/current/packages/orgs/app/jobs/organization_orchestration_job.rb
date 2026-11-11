# typed: strict
# frozen_string_literal: true

class OrganizationOrchestrationJob < OrchestrationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  queue_as :organization_orchestration
end
