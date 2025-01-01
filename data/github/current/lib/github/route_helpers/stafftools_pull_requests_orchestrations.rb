# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    def gh_stafftools_repository_pull_request_orchestrations_path(repo)
      expand_nwo_from :stafftools_repository_pull_request_orchestrations_path, repo
    end

    def gh_stafftools_repository_pull_request_orchestration_path(pull_request_orchestration)
      expand_from_pull_request_orchestration :stafftools_repository_pull_request_orchestration_path, pull_request_orchestration
    end

    def expand_from_pull_request_orchestration(helper, pull_request_orchestration)
      repo = pull_request_orchestration.repository
      # we can't call stafftools_repository_pull_request_orchestration_path directly without Sorbet warning the method doesn't exist,
      # even though it executes fine. I suspect that the route helpers are being mixed in later on, and `requires_ancestor { UrlHelpers }`
      # results in a dependency violation
      # sticking with `send` for now as the other helpers in this directory often do so and it works.
      send(helper, repo.owner, repo.name, pull_request_orchestration.id) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
    end
  end
end
