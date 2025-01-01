# typed: strict
# frozen_string_literal: true

class Stafftools::AdvancedSecurity::SubscriptionItemComponent < ApplicationComponent

  sig { returns(Business) }
  attr_reader :business

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig do params(
    business: Business,
    system_arguments: T.untyped
  ).void
  end
  def initialize(business:, **system_arguments)
    @business = business
    @system_arguments = system_arguments
  end

  sig { returns T::Boolean }
  def render?
    return false unless GitHub.billing_enabled?
    subscription_item.present?
  end

  sig { returns T.nilable(String) }
  def title
    if on_free_trial?
      return "Advanced Security Trial (Self-Serve)"
    end
    "Advanced Security Subscription Item (Self-Serve)"
  end

  sig { returns T.nilable(String) }
  def description
    if on_free_trial?
      return free_trial_ends_on ? "Trial ends on #{end_trial_date}" : "Missing pending trial cancellation!"
    end
    "Next billing date on #{next_billing_date}. #{seats} seats"
  end

  sig { returns T.nilable(String) }
  def end_trial_date
    free_trial_ends_on&.strftime("%b %d, %Y")
  end

  sig { returns T.nilable(Date) }
  memoize def free_trial_ends_on
    subscription_item&.ends_on
  end

  sig { returns T.nilable(String) }
  def next_billing_date
    subscription_item&.next_billing_date&.strftime("%b %d, %Y")
  end

  sig { returns T.nilable(String) }
  def seats
    subscription_item&.quantity&.to_s
  end

  sig { returns T::Boolean }
  memoize def on_free_trial?
    T.must(subscription_item).on_free_trial?
  end

  sig { returns T.nilable(Billing::Public::SubscriptionItem) }
  memoize def subscription_item
    business.advanced_security_subscription_item
  end
end
