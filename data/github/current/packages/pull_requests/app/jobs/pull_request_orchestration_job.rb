# typed: true
# frozen_string_literal: true

class PullRequestOrchestrationJob < OrchestrationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  queue_as do
    if FeatureFlag.vexi.enabled?(:pull_request_change_groups_dedicated_queue, default: false)
      _orchestration_id, type, _opts = T.unsafe(self).arguments
      if type == "PullRequests::Orchestrations::MakeChangeGroups"
        "pull_request_orchestration_change_groups"
      else
        "pull_request_orchestration"
      end
    else
      "pull_request_orchestration"
    end
  end
end
