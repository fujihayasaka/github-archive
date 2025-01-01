# typed: true
# frozen_string_literal: true

module Gist::NotifydAdapter
  # Overrides SubscribableThread#subscribe_in_notifyd?
  def subscribe_in_notifyd?(user, reason)
    return false if GitHub.enterprise?
    return false unless reason == "manual"
    FeatureFlag.vexi.enabled_or_raise?(:notifyd_primary_gist, user) || FeatureFlag.vexi.enabled_or_raise?(:notifyd_enable_gist_thread_subscriptions, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  # Overrides SubscribableThread#unsubscribe_in_notifyd?
  def unsubscribe_in_notifyd?(user)
    return false if GitHub.enterprise?
    FeatureFlag.vexi.enabled_or_raise?(:notifyd_primary_gist, user) || FeatureFlag.vexi.enabled_or_raise?(:notifyd_enable_gist_thread_subscriptions, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  # Overrides SubscribableThread#notifyd_primary?
  # Use Notifyd as primary storage
  def notifyd_primary?(user)
    return false if GitHub.enterprise?
    FeatureFlag.vexi.enabled_or_raise?(:notifyd_primary_gist, user) && FeatureFlag.vexi.enabled_or_raise?(:notifyd_enable_gist_thread_subscriptions, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end
end
