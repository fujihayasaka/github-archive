# typed: true
# frozen_string_literal: true

class DestroyMergeRefsJob < ApplicationJob
  use_replicas ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    allow_replication_lag: [
      ApplicationRecord::Spokes
    ]

  queue_as :maintain_tracking_ref

  retry_on_dirty_exit
  retry_on GitHub::DGit::ThreepcFailedToLock

  def perform(pull_request_id, options = {})
    pull = PullRequest.find_by(id: pull_request_id)

    return unless pull

    Failbot.push(
      "gh.repo.id": pull.repository_id,
      "gh.pull_request.id": pull.id
    )

    pull.destroy_merge_refs
  end
end
