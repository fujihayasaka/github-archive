# typed: true
# frozen_string_literal: true

# This job will backfill commit contribution summaries for contributors to the specified repository.
class BackfillCommitContributionSummariesJob < ApplicationJob

  queue_as :backfill_commit_contribution_summaries

  retry_on_dirty_exit

  # Only run one job at a time per repository
  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  resolve_tenant_context do |repo_id|
    Repositories::Public.resolve_tenant(id: repo_id)
  end

  def perform(repo_id, user_id: nil, backfill_timestamp: nil)
    if repo = ActiveRecord::Base.connected_to(role: :reading) { Repositories.domain.active_by_id(repo_id) }
      if user_id
        return unless user = with_read { User.find_by(id: user_id) }
      end

      with_write do
        CommitContributionSummary.backfill_repository(repo, user)
      end
    end
  end
end
