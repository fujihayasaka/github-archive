# typed: true
# frozen_string_literal: true

class RefPushDeleteJob < ApplicationJob
  queue_as :ref_push_delete
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  use_primaries ApplicationRecord::RepositoriesPushes

  def perform(repository_id, ref, pushed_at)
    GitHub.dogstats.distribution_time "ref_push_delete.duration" do
      repository = Repositories::Public.find_active(repository_id)
      return unless repository

      rows = RefPush.where(repository:, ref:, pushed_at: ..pushed_at).delete_all
      GitHub.dogstats.count("gh.ref_push_delete_job.ref_deleted", rows)
    end
  end
end
