# typed: strict
# frozen_string_literal: true

class BusinessOrchestrationJob < OrchestrationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  queue_as :business_orchestration
end
