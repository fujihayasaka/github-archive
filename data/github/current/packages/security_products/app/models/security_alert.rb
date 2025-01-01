# typed: true
# frozen_string_literal: true

# A placeholder class for a Newsies thread type subscription for a given
# repository to all security-related notifications, i.e Dependabot alerts,
# secret scanning, code scanning, repository advisories, etc.
class SecurityAlert

  # Returns the user ids that are subscribed to security alert related
  # notifications.
  #
  # This will be the user ids that meet at least one of the following conditions:
  #
  # - Subscribed to "All Activity" on the repository
  # - Subscribed to granular thread type subscriptions for "Security alerts"
  #
  def self.user_ids_subscribed_to_security_alerts(repository, user_ids)
    return user_ids unless user_ids.present?

    users = user_ids.map { |id| User.new(id: id) }
    subscriptions = GitHub.newsies.subscription_status_all(users, repository)

    # Over-notify instead of under-notify if Newsies is unavailable
    return user_ids unless subscriptions.success?

    subscriptions_by_user_id = user_ids.zip(subscriptions).to_h
    user_ids.select do |user_id|
      subscription = subscriptions_by_user_id[user_id]
      subscription.subscribed? || subscription.thread_type_only?(name)
    end
  end

  # Returns true if the user is subscribed to security alert related
  # notifications for the given repository, false otherwise.
  def self.user_subscribed_to_security_alerts?(repository, user)
    user_ids = [user.id]
    user_ids_subscribed_to_security_alerts(repository, user_ids) == user_ids
  end
end
