# typed: true
# frozen_string_literal: true

class Stafftools::Copilot::GrantFreeAccessComponent < ApplicationComponent
  attr_reader :copilot_user, :is_technical_preview_user, :free_user

  def initialize(copilot_user, is_technical_preview_user, free_user, subscription_item)
    @copilot_user              = copilot_user
    @is_technical_preview_user = is_technical_preview_user
    @free_user                 = free_user
    @subscription_item         = subscription_item
  end

  def render?
    !copilot_user.administrative_blocked? && !copilot_user.orgs_using_copilot_for_business.any? && !copilot_user.free_user_blocked?
  end

  def has_active_subscription?
    @subscription_item.present?
  end

  def has_trial_subscription?
    return false unless @subscription_item.present?
    @subscription_item.on_free_trial?
  end
end
