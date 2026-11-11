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

  SUPPORTED_SUBSCRIPTIONS_DOCS_URL = T.let(
    "https://docs.github.com/en/billing/reference/supported-payment-methods",
    String,
  )

  sig { returns(T::Boolean) }
  def has_selected_subscription?
    subscriptions.any? { |subscription| subscription[:selected] && billable_subscription?(subscription) }
  end

  sig { returns(T::Boolean) }
  def has_subscriptions?
    subscriptions.any?
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def billable_subscriptions
    subscriptions.select { |subscription| billable_subscription?(subscription) }
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def unsupported_subscriptions
    subscriptions.reject { |subscription| billable_subscription?(subscription) }
  end

  # Treats absence of `:billable` as billable for backwards compatibility when it's not provided
  sig { params(subscription: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def billable_subscription?(subscription)
    subscription[:billable] != false
  end

  sig { returns(String) }
  def unsupported_subscriptions_summary
    count = unsupported_subscriptions.size
    count == 1 ? "1 unsupported subscription" : "#{count} unsupported subscriptions"
  end
end
