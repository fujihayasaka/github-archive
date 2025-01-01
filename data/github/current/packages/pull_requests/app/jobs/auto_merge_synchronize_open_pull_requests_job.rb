# typed: true
# frozen_string_literal: true

class AutoMergeSynchronizeOpenPullRequestsJob < ApplicationJob
  queue_as :auto_merge

  def perform(repository:, base_ref:)
    repository.pull_requests.includes(:auto_merge_request).open_pulls.for_base_ref(base_ref).where(issues: { repository_id: repository.id }).find_each do |pull|
      pull.enqueue_auto_merge_job_if_enabled
    end
  end
end
