# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Public: Create subscribed issues for events
class CreateSubscribedIssueEventsJob < ApplicationJob
  queue_as :kubernetes_notifications

  retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer

  retry_on_dirty_exit

  def perform(issue_id, user_ids)
    begin
      issue = Issue.find(issue_id)
    rescue ActiveRecord::RecordNotFound
      GitHub.dogstats.increment("notifications.create_subscribed_issue_events.issue_not_found")
      raise
    end

    User.where(id: user_ids).find_each do |user|
      next unless issue.subscribable_by?(user)
      ignore_duplicate_records do
        issue.throttle_writes { issue.events.create(actor: user, event: "subscribed") }
      end
    end
  end

  # Ignores duplicate record creation for the duration of the block. We use
  # unique indexes to prevent records in various places.
  def ignore_duplicate_records
    yield
  rescue ActiveRecord::RecordNotUnique
    GitHub.dogstats.increment("notifications.create_subscribed_issue_events.record_not_unique")
  end
end
