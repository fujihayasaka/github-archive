# typed: true
# frozen_string_literal: true

module Gist::NotifydAdapter
  # Overrides SubscribableThread#subscribe_in_notifyd?
  def subscribe_in_notifyd?(user, reason)
    return false if GitHub.enterprise?
    reason == "manual"
  end

  # Overrides SubscribableThread#unsubscribe_in_notifyd?
  def unsubscribe_in_notifyd?(user)
    !GitHub.enterprise?
  end

  # Overrides SubscribableThread#notifyd_primary?
  # Use Notifyd as primary storage
  def notifyd_primary?(user)
    !GitHub.enterprise?
  end
end
