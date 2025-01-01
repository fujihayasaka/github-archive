# typed: strict
# frozen_string_literal: true

class Azure::SubscriptionSelectionDialogComponent < ApplicationComponent

  sig { returns(Billing::Types::OrgOrBusiness) }
  attr_reader :target

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  attr_reader :subscriptions

  sig { returns(T::Boolean) }
  attr_reader :fetch_failed

  sig { params(target: Billing::Types::OrgOrBusiness, subscriptions: T::Array[T::Hash[Symbol, T.untyped]], fetch_failed: T::Boolean).void }
  def initialize(target, subscriptions, fetch_failed)
    @target = target
    @subscriptions = subscriptions
    @fetch_failed = fetch_failed
  end

  sig { returns(String) }
  def form_action_path
    case target = self.target
    when Organization
      azure_linked_subscriptions_path(account_type: "organization", account_id: target.display_login)
    when Business
      billing_settings_selected_azure_subscription_path
    else
      T.absurd(target)
    end
  end

  sig { returns(T::Boolean) }
  def has_selected_subscription?
    subscriptions.any? { |subscription| subscription[:selected] }
  end

  sig { returns(T::Boolean) }
  def has_subscriptions?
    subscriptions.any?
  end

  sig { returns(T::Boolean) }
  def should_validate_permissions
    target.feature_flag_enabled?(:validate_azure_subscription_permissions, default: true)
  end
end
