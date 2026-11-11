# typed: strict
# frozen_string_literal: true

module Copilot
  class AicSeatUsageComponent < ApplicationComponent
    BUDGET_STATE_NO_BUDGET = :no_budget
    BUDGET_STATE_HAS_BUDGET = :has_budget
    BUDGET_STATE_BLOCKED = :blocked

    # This component renders synchronously during the page request, so bound the
    # billing-platform calls with an explicit timeout. Without one, a slow
    # response can consume the entire request budget and time out the page. On
    # timeout the client returns Billing::Platform::Api::Error, which both
    # #fetch_budget_data and #usage_blocked? already handle by failing closed
    # (blocking usage) rather than 500-ing.
    BILLING_PLATFORM_TIMEOUT_SECONDS = T.let(1.0, Float)

    sig { params(copilot_user: Copilot::User).void }
    def initialize(copilot_user:)
      @copilot_user = copilot_user
      @budget_state = T.let(BUDGET_STATE_NO_BUDGET, Symbol)
      @percent_used = T.let(0.0, Float)
    end

    sig { void }
    def before_render
      resolve_budget_state
    end

    sig { returns(T::Boolean) }
    def render?
      public_user = Copilot::Public::User.for(@copilot_user.user_object)

      return false if public_user.has_ci_access?
      return false unless public_user.has_cb_access? || public_user.has_ce_access?
      return false unless billable_customer_id.present?

      @copilot_user.use_token_based_billing?
    end

    sig { returns(T::Boolean) }
    def usage_exhausted?
      return false if usage_blocked?

      !can_proceed_with_usage? || (@budget_state == BUDGET_STATE_HAS_BUDGET && @percent_used >= 100.0)
    end

    sig { returns(T::Boolean) }
    def usage_blocked?
      @budget_state == BUDGET_STATE_BLOCKED || cpwu_response.error.is_a?(::Billing::Platform::Api::Error)
    end

    sig { returns(T::Boolean) }
    def has_monthly_budget?
      @budget_state == BUDGET_STATE_HAS_BUDGET
    end

    sig { returns(String) }
    def usage_limit_label
      unless has_monthly_budget? || usage_blocked?
        return "You have no monthly limit on AI credits usage set by your organization."
      end

      format_reset_label(Time.current.next_month.beginning_of_month.to_i)
    end

    sig { returns(T::Boolean) }
    def show_banner?
      usage_blocked? || usage_exhausted?
    end

    sig { returns(String) }
    def banner_text
      if usage_blocked?
        provider = seat_provider_name
        if provider.present?
          "Usage is currently blocked by #{provider}. Contact your admin to resume usage."
        else
          "Usage is currently blocked. Contact your admin to resume usage."
        end
      else
        "Usage paused until monthly limit resets. Contact your admin to request additional usage."
      end
    end

    private

    sig { void }
    def resolve_budget_state
      result = fetch_budget_data
      @budget_state = result[:state]
      @percent_used = result[:percent]
    end

    sig { returns({ state: Symbol, percent: Float }) }
    memoize def fetch_budget_data
      # If we can't determine a billable customer ID, we should assume the user cannot proceed with usage anyway.
      return { state: BUDGET_STATE_BLOCKED, percent: 0.0 } unless billable_customer_id

      response = billing_client.get_all_budgets(
        customer_id: billable_customer_id,
        user_id: @copilot_user.id.to_s,
        budget_target: "premium_requests",
      )

      # Fail closed from the billing platform and block usage if we get an error response.
      return { state: BUDGET_STATE_BLOCKED, percent: 0.0 } if response.is_a?(::Billing::Platform::Api::Error)

      effective_budget = response[:effective_budget]
      # If we can't find an effective budget for the user, assume there's no budget rather than blocking usage
      return { state: BUDGET_STATE_NO_BUDGET, percent: 0.0 } unless effective_budget

      budget = effective_budget[:budgetState]
      # If we cant find a specific budget state for the user, assume there's no budget rather than blocking usage
      return { state: BUDGET_STATE_NO_BUDGET, percent: 0.0 } unless budget

      # If for some reason target is zero or less, the budget is consumed
      return { state: BUDGET_STATE_HAS_BUDGET, percent: 100.0 } if budget[:targetAmount] <= 0.0

      percent = ((budget[:currentAmount] / budget[:targetAmount]) * 100.0).clamp(0.0, 100.0)
      { state: BUDGET_STATE_HAS_BUDGET, percent: percent }
    end

    sig { returns(T::Boolean) }
    memoize def can_proceed_with_usage?
      return false if usage_blocked?
      return false unless billable_customer_id.present?

      !!cpwu_response.can_proceed
    end

    sig { returns(::Billing::Platform::CanProceedWithUsage::Response) }
    memoize def cpwu_response
      timeout = if @copilot_user.feature_flag_enabled?(:copilot_settings_billing_timeout, default: false)
        BILLING_PLATFORM_TIMEOUT_SECONDS
      end

      ::Billing::Platform::CanProceedWithUsage.call(
        ::Billing::Platform::CanProceedWithUsage::RequestParams.new(
          customer_id: billable_customer_id || "",
          product: "copilot",
          sku: ::Billing::OveragePolicyConfiguration::COPILOT_AI_UNIT,
          actor_id: @copilot_user.id
        ),
        timeout: timeout,
      )
    end

    sig { returns(::Billing::Platform::Api::Client) }
    memoize def billing_client
      if @copilot_user.feature_flag_enabled?(:copilot_settings_billing_timeout, default: false)
        ::Billing::Platform::Api::Client.new(timeout: BILLING_PLATFORM_TIMEOUT_SECONDS)
      else
        ::Billing::Platform::Api::Client.new
      end
    end

    sig { returns(T.nilable(Integer)) }
    memoize def billable_customer_id
      explicit_id = @copilot_user.billable_customer_id
      return explicit_id if explicit_id.present?

      # A user will likely only have an explicit id set if they have seats from multiple enterprises.
      # So now we need to get all customer ids associated with this user.
      ids = Copilot::Public::User.for(@copilot_user.user_object).copilot_customer_ids

      # If they have multiple customer ids, we can't be sure which one to use, so return nil.
      return nil if ids.size != 1

      # If they have exactly one, return it.
      ids.first
    end

    sig { returns(T.nilable(String)) }
    def seat_provider_name
      @copilot_user.copilot_provider&.display_login
    end

    sig { params(epoch: Integer, time_zone: ActiveSupport::TimeZone).returns(String) }
    def format_reset_label(epoch, time_zone: ActiveSupport::TimeZone["UTC"])
      return "" if epoch == 0

      reset_time = Time.zone.at(epoch).in_time_zone(time_zone)
      now = Time.current.in_time_zone(time_zone)

      distance = reset_time - now
      return "" if distance <= 0

      relative = if distance < 1.hour
        minutes = (distance / 60).ceil
        "#{minutes} #{"minute".pluralize(minutes)}"
      elsif distance < 1.day
        hours = (distance / 1.hour).ceil
        "#{hours} #{"hour".pluralize(hours)}"
      else
        days = (distance / 1.day).ceil
        "#{days} #{"day".pluralize(days)}"
      end

      formatted_date = reset_time.strftime("%b %-d, %Y")
      "Resets in #{relative} on #{formatted_date}"
    end
  end
end
