# typed: true
# frozen_string_literal: true

# Public: Moves issue-thread notification entries between notification_entries and
# spammy_notification_entries for each issue authored by a spammy user. Iterates through
# all issues authored by the user and enqueues a Newsies::UpdateNotificationsSpamStatusJob
# per issue. Each per-issue job checks the thread's own spammy? status and moves entries
# accordingly.
#
# Enqueued by: UpdateTableUserHiddenJob (app/jobs/update_table_user_hidden_job.rb) alongside
# ToggleNotificationsForSpammyUsersJob when a user's spam status changes.
class ToggleIssueNotificationsForSpammyUsersJob < ApplicationJob
  queue_as :entries_maintenance

  retry_on GitHub::Restraint::UnableToLock

  retry_on_dirty_exit

  use_replicas ApplicationRecord::Mysql1,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories

  # Execute this job with the given user ID.
  #
  # user_id - The Integer ID of the user whose issue notifications should
  # be purged.
  #
  def perform(user_id, _mode = nil, _opts = {})
    return false unless user = User.find_by(id: user_id)

    Failbot.push({ "gh.user.id": user_id })

    restraint.lock!("toggle_issue_notifications_visibility_for_user_#{user_id}", 1, 30.minutes) do
      user.issues.includes(:repository).find_each do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        repo = issue.repository
        next unless repo
        GitHub.newsies.async_update_notifications_spam_status(repo, issue)
      end
    end
  end

  private

  def restraint
    @restraint ||= GitHub::Restraint.new
  end
end
