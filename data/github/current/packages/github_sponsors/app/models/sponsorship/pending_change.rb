# typed: strict
# frozen_string_literal: true

# PORO representing a sponsorship change
#
# A high-level facade over lower-level Billing::PendingSubscriptionItemChange with Sponsors-specific semantics.
class Sponsorship::PendingChange < T::Struct
  extend T::Sig

  class Type < T::Enum
    enums do
      Activation = new
      Cancellation = new
      Downgrade = new
      Upgrade = new
      # it's possible for a pending change to match the current state and result in no operation (NOP)
      NOP = new
    end
  end

  prop :current_subscription_item, T.nilable(Billing::SubscriptionItem)
  prop :pending_subscription_item_change, Billing::PendingSubscriptionItemChange

  sig { returns Type }
  def type
    current_quantity = current_subscription_item&.quantity || 0
    pending_quantity = pending_subscription_item_change.quantity

    current_price = current_subscription_item&.subscribable&.monthly_price_in_cents || 0
    pending_price = pending_subscription_item_change.subscribable&.monthly_price_in_cents || 0

    if pending_quantity.zero? && current_quantity.positive?
      Type::Cancellation
    elsif pending_quantity.positive? && current_quantity.zero?
      Type::Activation
    elsif pending_price < current_price
      Type::Downgrade
    elsif pending_price > current_price
      Type::Upgrade
    else
      Type::NOP
    end
  end

  sig { returns T::Boolean }
  def activation?
    type == Type::Activation
  end

  sig { returns String }
  def name
    change_type = type
    case change_type
    when Type::Cancellation
      "pending cancellation"
    when Type::Activation
      "pending activation"
    when Type::Downgrade
      "pending downgrade"
    when Type::Upgrade
      "pending upgrade"
    when Type::NOP
      "pending change"
    else
      T.absurd(change_type)
    end
  end

  sig { returns String }
  def to_s
    name
  end

  sig { returns String }
  def description
    change_type = type
    change_type_description = case change_type
    when Type::Cancellation, Type::Activation, Type::NOP
      name
    when Type::Downgrade, Type::Upgrade
      "#{name} to #{new_tier}"
    else
      T.absurd(change_type)
    end

    formatted_active_on = active_on.strftime("%b %d, %Y")
    "#{change_type_description} effective #{formatted_active_on}"
  end

  sig { returns Date }
  def active_on
    pending_subscription_item_change.active_on
  end

  sig { returns T.nilable(SponsorsTier) }
  def new_tier
    # suppress the tier if it only exists on the pending sub item change to ensure a cancellation or it's a no-op.
    return nil if [Type::Cancellation, Type::NOP].include?(type)
    pending_subscription_item_change.subscribable
  end

  # Public: Stop a pending change from being applied.
  #
  # Returns Boolean with true indicating success
  sig { params(actor: User).returns(T::Boolean) }
  def cancel(actor:)
    change_type = type
    case change_type
    when Type::Activation
      sponsorship = current_subscription_item&.sponsorship
      sponsorship&.cancel_pending_activation
    when Type::Cancellation
      pending_subscription_item_change.instrument_undo_sponsorship_cancellation(actor: actor)
    when Type::NOP, Type::Downgrade, Type::Upgrade
      # no side effects necessary
    else
      T.absurd(change_type)
    end

    !!pending_subscription_item_change.destroy
  end

  private

  sig { returns T.nilable(SponsorsTier) }
  def current_tier
    current_subscription_item&.subscribable
  end
end
