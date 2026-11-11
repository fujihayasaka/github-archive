# typed: true
# frozen_string_literal: true

module MemexProject::NotifydAdapter
  # SubscribableThread is included in MemexProject::NewsiesAdapter
  # See packages/planning/app/models/memex_project/newsies_adapter.rb

  # Overrides SubscribableThread#subscribe_in_notifyd?
  def subscribe_in_notifyd?(user, reason)
    GitHub.runtime.dotcom?
  end

  # Overrides SubscribableThread#unsubscribe_in_notifyd?
  def unsubscribe_in_notifyd?(user)
    GitHub.runtime.dotcom?
  end

  # Overrides SubscribableThread#notifyd_primary?
  # Use Notifyd as primary storage
  def notifyd_primary?(user)
    GitHub.runtime.dotcom?
  end
end
