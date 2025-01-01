# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Reminders
  class CommitStatusFailedJob < RealTimeJob
    include CiFailed

    resolve_tenant_context do |kwargs|
      statuses = Statuses.domain.current_statuses_for_shas(repository_id: kwargs[:repository_id], shas: [kwargs[:sha]])

      commit_status = statuses.detect { |status| status.id == kwargs[:commit_status_id] }
      repository = commit_status&.repository
      if repository
        Business.find_by(id: repository.tenant_id)
      end
    end

    def perform(commit_status_id:, repository_id:, sha:, event_at:, transaction_id:)
      statuses = Statuses.domain.current_statuses_for_shas(repository_id: repository_id, shas: [sha])

      commit_status = statuses.detect { |status| status.id == commit_status_id }
      return unless commit_status.present?
      return unless commit_status.failed_or_errored?

      pull_requests = commit_status.related_pull_requests
      return if pull_requests.empty?

      events = ci_failed_events(pull_requests, commit_status)

      queue_reminder_events(events)
    end

    private

    def target_name(status)
      status.context
    end

    def target_url(status)
      status.target_url
    end
  end
end
