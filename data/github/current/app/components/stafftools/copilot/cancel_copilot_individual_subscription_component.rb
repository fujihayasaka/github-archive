# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::CancelCopilotIndividualSubscriptionComponent < ApplicationComponent
  extend T::Helpers

  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { params(copilot_user: Copilot::User).void }
  def initialize(copilot_user)
    @copilot_user = copilot_user
  end

  sig { returns(T::Boolean) }
  def show_component?
    copilot_user.has_copilot_access? &&
    (copilot_user.has_pro_subscription? || copilot_user.has_pro_plus_subscription? || copilot_user.has_max_subscription?)
  end

  sig { returns(String) }
  def product_name
    copilot_subscription_item&.name.delete_prefix("GitHub ")
  end

  sig { returns(T.nilable(Billing::Public::SubscriptionItem)) }
  memoize def copilot_subscription_item
    copilot_user.copilot_active_subscription_item
  end

  sig { returns(String) }
  def subscription_type_param
    if copilot_user.has_pro_subscription?
      "pro"
    elsif copilot_user.has_pro_plus_subscription?
      "pro_plus"
    elsif copilot_user.has_max_subscription?
      "max"
    else
      "unknown"
    end
  end
end
