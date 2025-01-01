# typed: true
# frozen_string_literal: true

class Businesses::Billing::AdvancedSecurity::PendingChangeNoticeComponent < ApplicationComponent
  sig { returns Business }
  attr_reader :business

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig { params(business: Business, system_arguments: Primer::SystemArgumentsValue).void }
  def initialize(business:, **system_arguments)
    @business = business
    @system_arguments = system_arguments
    @system_arguments[:tag] = :div
    @system_arguments[:classes] = class_names("Box-footer", "flash-warn", "rounded-bottom-2", @system_arguments[:classes])
  end

  def render?
    pending_change.present?
  end

  sig { returns T.nilable(Billing::PendingSubscriptionItemChange) }
  memoize def pending_change
    business.advanced_security_subscription_change
  end

  sig { returns String }
  memoize def pending_change_active_on
    return "" if pending_change.nil?
    T.must(pending_change).active_on.strftime("%b %d, %Y")
  end

  sig { returns String }
  memoize def new_price
    return "" if pending_change.nil?
    business.advanced_security_price(seats: T.must(pending_change).quantity).format(no_cents_if_whole: true)
  end

  sig { returns String }
  memoize def duration
    pending_change&.subscribable&.billing_cycle
  end

  sig { returns T::Boolean }
  memoize def has_pending_cancellation?
    !!pending_change&.cancellation?
  end
end
