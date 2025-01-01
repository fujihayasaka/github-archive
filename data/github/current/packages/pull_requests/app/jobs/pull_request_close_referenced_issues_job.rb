# typed: true
# frozen_string_literal: true
class PullRequestCloseReferencedIssuesJob < ApplicationJob
  # We write to IssuesPullRequests in a connected_to(:writing) block but we delcare
  # it as a replica here so we wait for replication lag on this cluster.
  use_replicas ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    allow_replication_lag: [
      ApplicationRecord::Notify,
      ApplicationRecord::Permissions,
      ApplicationRecord::Configurations
    ]

  queue_as :update_close_issue_references
  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on SpokesAPI::ResourceExhausted, wait: :polynomially_longer

  def perform(pull_request:, actor:)
    if actor&.bot?
      actor.async_load_installation_for(pull_request.repository).sync
    end

    pull_request.close_issues_on_merge(actor)
  end
end
