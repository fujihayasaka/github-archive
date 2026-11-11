# typed: true
# frozen_string_literal: true

module Issue::NotifydAdapter
  extend T::Helpers

  requires_ancestor { Issue }

  # Overrides SubscribableThread#subscribe_in_notifyd?
  def subscribe_in_notifyd?(user, reason)
    return false if GitHub.enterprise?
    return false if pull_request?
    return false unless reason == "manual"
    Notifyd::Flags.new(user).enable_issue_thread_subscriptions?
  end

  # Overrides SubscribableThread#unsubscribe_in_notifyd?
  def unsubscribe_in_notifyd?(user)
    return false if GitHub.enterprise?
    return false if pull_request?
    Notifyd::Flags.new(user).enable_issue_thread_subscriptions?
  end

  # Overrides SubscribableThread#notifyd_primary?
  # Use Notifyd as primary storage
  def notifyd_primary?(user)
    return false if GitHub.enterprise?
    return false if pull_request?
    flags = Notifyd::Flags.new(user)
    return false unless flags.enable_issue_thread_subscriptions?
    flags.enable_issue_notifications?
  end
end
