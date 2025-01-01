# typed: true
# frozen_string_literal: true

class NotifyPullRequestCommitChecksUpdatedJob < ApplicationJob

  queue_as :notify_pull_request_commit_checks_updated
  retry_on_dirty_exit

  resolve_tenant_context do |repository_id, _head_sha|
    Repositories::Public.resolve_tenant(id: repository_id)
  end

  def perform(repository_id, head_sha)
    repository = Repository.find_by(id: repository_id)
    return unless repository

    repository.pull_requests.where(head_sha:).each do |pull_request|
      Platform::Schema.subscriptions.trigger(:pull_request_info_for_list_view_updated, { id: pull_request.global_relay_id }, object: { commit_checks_updated: true })
    end
  end
end
