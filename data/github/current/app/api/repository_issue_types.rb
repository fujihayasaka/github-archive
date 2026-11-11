# typed: true
# frozen_string_literal: true

class Api::RepositoryIssueTypes < Api::App
  include Api::Issues::EnsureIssuesEnabled

  get "/repositories/:repository_id/issue-types", operation_id: "repos/list-issue-types" do
    repo = find_repo!
    deliver_error!(404) unless FeatureFlag.vexi.enabled?(:repo_issue_types_api, repo, default: false)
    deliver_error!(404) unless repo.owner.issue_types_enabled?

    control_access :list_repo_issue_types,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    issue_types = Issues.domain.issue_types.by_repository(repo)

    deliver :type_hash, issue_types
  end
end
