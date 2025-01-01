# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true


# Public: Purges issue notifications originating from a user that flagged as "spammy".
#
# The methods that calculate the follower/following count already know to exclude spammy users. We
# just have to run them.
class ToggleIssueNotificationsForSpammyUsersJob < ApplicationJob
  queue_as :toggle_spammy_notifications

  retry_on GitHub::Restraint::UnableToLock

  retry_on_dirty_exit

  # Execute this job with the given user ID.
  #
  # user_id - The Integer ID of the user whose issue notifications should
  # be purged.
  #
  def perform(user_id, _mode = nil, _opts = {})
    return false unless user = User.find_by(id: user_id)

    Failbot.push({ "gh.user.id": user_id })

    restraint.lock!("toggle_issue_notifications_visibility_for_user_#{user_id}", 1, 30.minutes) do
      user.issues.includes(:repository).find_each do |issue|
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
