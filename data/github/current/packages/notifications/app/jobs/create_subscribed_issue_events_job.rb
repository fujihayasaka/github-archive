# typed: true
# frozen_string_literal: true

# Public: Batch-creates IssueEvent records with event: "subscribed" for a set of users
# on a given issue. Each user is verified as eligible via issue.subscribable_by?(user)
# before the record is created; duplicates are silently ignored.
#
# Enqueued by: Issue#subscribe_all_with_event (packages/issues/app/models/issue.rb) when
# multiple users need to be subscribed to an issue at once. Users are sliced into batches
# of GitHub.subscribed_users_batch_size and each batch is enqueued as a separate job.
class CreateSubscribedIssueEventsJob < ApplicationJob
  queue_as :thread_subscribe

  retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer

  retry_on_dirty_exit

  use_replicas ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories

  def perform(issue_id, user_ids)
    begin
      issue = Issue.find(issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    rescue ActiveRecord::RecordNotFound
      GitHub.dogstats.increment("notifications.create_subscribed_issue_events.issue_not_found")
      raise
    end

    User.where(id: user_ids).find_each do |user|
      next unless issue.subscribable_by?(user)
      ignore_duplicate_records do
        issue.throttle_writes { issue.events.create(actor: user, event: "subscribed") } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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
