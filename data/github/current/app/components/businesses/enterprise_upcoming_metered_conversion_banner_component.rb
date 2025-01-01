# typed: true
# frozen_string_literal: true

# This component renders a banner for enterprises with upcoming transitions to metered billing
class Businesses::EnterpriseUpcomingMeteredConversionBannerComponent < ApplicationComponent
  attr_reader :business, :current_user

  def initialize(business:, current_user:)
    @business = business
    @current_user = current_user
  end

  def render?
    return false unless controller.controller_name == "enterprise_licensing" && controller.action_name == "show"
    return false unless current_user&.feature_flag_enabled?(:licensing_self_serve_metered_ui, default: false)
    return false unless business.owner?(current_user)
    return false if business.metered_plan?
    return false if business.trial?

    transition.present?
  rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
    false
  end

  def transition
    business.customer&.licensing_model_transitions
      &.where(
        status: "scheduled",
        licensing_model: "metered"
      )
      &.where("transition_date >= ?", Date.current)
      &.order(:transition_date)
      &.first
  rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
    nil
  end
  memoize :transition

  def transition_date
    if transition.present?
      transition.transition_date.strftime("%B %d, %Y")
    end
  end

  def cancellation_deadline
    if transition.present?
      (transition.transition_date - 1.day).strftime("%B %d, %Y")
    end
  end

  def banner_color
    "color-bg-accent color-border-accent"
  end

  def text_color
    "color-fg-default"
  end

  def text_color_symbol
    :accent
  end

  def font_weight
    "font-weight: bold"
  end
end
