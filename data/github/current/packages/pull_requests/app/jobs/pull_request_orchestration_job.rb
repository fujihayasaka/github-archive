# typed: true
# frozen_string_literal: true

class PullRequestOrchestrationJob < OrchestrationJob
  use_primaries ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::IssuesPullRequests

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

  def perform(orchestration_id, type, kicked: false)
    klass = type.constantize
    orchestration = klass.find(orchestration_id)

    orchestration.execute

    if kicked
      GitHub.dogstats.increment("#{orchestration.base_orchestration_name}.kick_finish", tags: ["type:#{orchestration.type}", "state:#{orchestration.state}"])
    end
  end
end
