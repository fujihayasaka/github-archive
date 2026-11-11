# typed: strict
# frozen_string_literal: true

#
# Stafftools component for displaying cached consumptive user data from the CopilotLimiter service.
# This component safely fetches and displays quota information for debugging purposes.
#
class Stafftools::Copilot::CachedConsumptiveUserComponent < ApplicationComponent
  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  attr_reader :consumptive_user

  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { returns(T::Boolean) }
  def render?
    FeatureFlag.vexi.enabled?("copilot_show_cached_consumptive_user", @copilot_user.user_object, default: false)
  end

  sig { params(copilot_user: Copilot::User).void }
  def initialize(copilot_user)
    @copilot_user = copilot_user

    unless copilot_user.user_object.present?
      @consumptive_user = {}
      return
    end

    tracking_id = copilot_user.user_object.analytics_tracking_id
    if tracking_id.blank?
      @consumptive_user = {}
      return
    end

    @consumptive_user = T.let(
      fetch_consumptive_user(tracking_id),
      T.nilable(T::Hash[Symbol, T.untyped])
    )
  end

  private

  sig { params(tracking_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def fetch_consumptive_user(tracking_id)
    response = CopilotLimiter::Twirp.quota_client.get_consumptive_user(copilot_tracking_id: tracking_id)

    return nil if response.empty?

    response.dup.tap do |result|
      result[:reset_date] = format_reset_date(result[:reset_date]) if result[:reset_date]
      result.delete(:use_token_based_billing) if result[:use_token_based_billing].nil?
      result[:cu_cached_at].present? ? result[:cu_cached_at] = format_epoch(result[:cu_cached_at]) : result.delete(:cu_cached_at)
      result[:cpwu_cached_at].present? ? result[:cpwu_cached_at] = format_epoch(result[:cpwu_cached_at]) : result.delete(:cpwu_cached_at)
      result.delete(:can_proceed_with_usage) if result[:can_proceed_with_usage].nil?
      result[:applicable_budgets].present? ? result[:applicable_budgets] = parse_budgets(result[:applicable_budgets]) : result.delete(:applicable_budgets)
      result[:billable_owner_trust_tier].present? ? result[:billable_owner_trust_tier] = result[:billable_owner_trust_tier].to_s : result.delete(:billable_owner_trust_tier)
      result[:cpwu_status].present? ? result[:cpwu_status] = result[:cpwu_status].to_s : result.delete(:cpwu_status)
      result[:user_level_budget].present? ? result[:user_level_budget] = format_user_level_budget(result[:user_level_budget]) : result.delete(:user_level_budget)
    end
  rescue TwirpHelper::TwirpError => e
    # Log the error but don't crash the component
    GitHub.logger.error("Error fetching consumptive user data", {
      "code.function": "fetch_consumptive_user",
      "code.namespace": self.class.name,
      "error.message": e.message,
      "error.class": e.class.name
    })
    {}
  end

  sig { params(reset_date: T.untyped).returns(T::Hash[Symbol, Integer]) }
  def format_reset_date(reset_date) = { year: reset_date.year, month: reset_date.month, day: reset_date.day }

  sig { params(epoch: T.nilable(Integer)).returns(T.nilable(String)) }
  def format_epoch(epoch)
    return nil unless epoch&.positive?

    Time.at(epoch).utc.iso8601
  end

  sig { params(budgets: T.nilable(String)).returns(T.nilable(T::Array[T.untyped])) }
  def parse_budgets(budgets)
    return nil if budgets.nil?

    JSON.parse(budgets)
  rescue JSON::ParserError
    nil
  end

  sig { params(budget: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def format_user_level_budget(budget)
    {
      has_budget: budget.has_budget,
      target_amount: budget.target_amount,
      current_amount: budget.current_amount,
      overage_amount: budget.overage_amount,
      remaining: budget.remaining,
      percent_remaining: budget.percent_remaining,
      cached_at: format_epoch(budget.cached_at),
    }
  end
end
