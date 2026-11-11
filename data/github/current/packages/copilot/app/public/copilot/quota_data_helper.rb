# typed: strict
# frozen_string_literal: true

module Copilot
  module QuotaDataHelper
    extend ActionView::Helpers::NumberHelper

    OverageData = T.type_alias do
      {
        amount_spent: String,
        budget_amount: String,
        budget_uuid: T.nilable(String),
        budget_target_amount: Integer,
        percent_used: Float,
        reset_label: String,
        overage_enabled: T::Boolean,
        budget_exists: T::Boolean,
      }
    end

    SpendingInfo = T.type_alias do
      {
        status: Symbol,
        overage_amount: Float,
        limit: Float,
        limit_reached: T::Boolean,
        updated_at: Integer,
      }
    end

    # Fetches budget definition and current spend for a customer's premium_requests budget.
    # Returns a hash with :uuid, :target_amount, and :current_spend, or nil if no budget exists.
    sig { params(client: ::Billing::Platform::Api::Client, customer_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) } # rubocop:disable Sorbet/ForbidTUntyped
    def self.fetch_budget_spend(client:, customer_id:)
      budget_key = {
        customerId: customer_id,
        targetType: "CustomerResource",
        targetId: customer_id,
        pricingTargetType: "BundlePricing",
        pricingTargetId: "premium_requests",
      }

      response = client.get_budget(key: budget_key)
      return if response.is_a?(::Billing::Platform::Api::Error)

      budget = response[:budget]
      return unless budget

      budget_uuid = budget[:uuid]
      target_amount = budget[:targetAmount].to_i

      # GetBudgetResponse only contains the budget definition -- no budgetState.
      # Fetch spend data via get_budget_by_uuid which returns budgetState.
      current_spend = 0.0
      if budget_uuid.present?
        uuid_response = client.get_budget_by_uuid(customer_id:, uuid: budget_uuid)
        unless uuid_response.is_a?(::Billing::Platform::Api::Error)
          budget_obj = uuid_response[:budget]
          current_spend = budget_obj.current_amount if budget_obj
        end
      end

      { uuid: budget_uuid, target_amount:, current_spend: }
    end

    sig { params(budget_uuid: T.nilable(String), budget_amount: Integer, current_spend: Float, overage_permitted: T::Boolean, overage_reset_label: String).returns(OverageData) }
    def self.build_overage_from_budget_values(budget_uuid:, budget_amount:, current_spend:, overage_permitted:, overage_reset_label:)
      percent_used = self.real_budget_percent_used(current_spend, budget_amount)

      {
        amount_spent: number_to_currency(current_spend),
        budget_amount: number_to_currency(budget_amount, precision: 0),
        budget_uuid:,
        budget_target_amount: budget_amount,
        percent_used:,
        reset_label: overage_reset_label,
        overage_enabled: overage_permitted,
        budget_exists: budget_uuid.present?,
      }
    end

    sig { params(overage_permitted: T::Boolean, overage_reset_label: String).returns(OverageData) }
    def self.default_overage_data(overage_permitted:, overage_reset_label:)
      {
        amount_spent: "$0.00",
        budget_amount: "$0",
        budget_uuid: nil,
        budget_target_amount: 0,
        percent_used: 0.0,
        reset_label: overage_reset_label,
        overage_enabled: overage_permitted,
        budget_exists: false,
      }
    end

    sig { params(current_spend: Float, budget_amount: Integer).returns(Float) }
    def self.real_budget_percent_used(current_spend, budget_amount)
      if budget_amount <= 0
        current_spend > 0 ? 100.0 : 0.0
      else
        ((current_spend / budget_amount.to_f) * 100).clamp(0.0, 100.0)
      end
    end

    sig { params(reset_date: Date, time_zone: ActiveSupport::TimeZone).returns(String) }
    def self.format_reset_label(reset_date, time_zone: ActiveSupport::TimeZone["UTC"])
      now = Time.current.in_time_zone(time_zone)
      # The backend resets quotas at midnight UTC on reset_date.
      # Localize that UTC instant to the user's timezone to show the correct local date/time.
      reset_time = localize_utc_reset(reset_date, time_zone)
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

    sig { params(raw_percent: Float).returns(Float) }
    def self.format_percentage_used(raw_percent)
      raw_percent.clamp(0.0, 100.0).to_d.truncate(2).to_f
    end

    sig { params(copilot_user: Copilot::User, time_zone: ActiveSupport::TimeZone).returns(String) }
    def self.short_usage_reset_date(copilot_user, time_zone: ActiveSupport::TimeZone["UTC"])
      reset_date = copilot_user.quota_reset_date
      # Localize the UTC reset instant to the user's timezone to show the correct local date.
      localized_reset = localize_utc_reset(reset_date, time_zone)
      localized_reset.strftime("%b %-d")
    end

    sig { params(copilot_user: Copilot::User, time_zone: ActiveSupport::TimeZone).returns(String) }
    def self.iso_usage_reset_date(copilot_user, time_zone: ActiveSupport::TimeZone["UTC"])
      reset_date = copilot_user.quota_reset_date
      localized_reset = localize_utc_reset(reset_date, time_zone)
      localized_reset.strftime("%Y-%m-%d")
    end

    sig { params(reset_date: Date, time_zone: ActiveSupport::TimeZone).returns(ActiveSupport::TimeWithZone) }
    def self.localize_utc_reset(reset_date, time_zone)
      ActiveSupport::TimeZone["UTC"].local(reset_date.year, reset_date.month, reset_date.day).in_time_zone(time_zone)
    end
    private_class_method :localize_utc_reset

    # Dev-only key used by script/setup-copilot-user to inject a synthetic overage amount
    # (in dollars) so the Copilot checkout/billing-summary UI can be exercised without a
    # running billing-platform service. Read only in development.
    DEV_SPENDING_OVERRIDE_KV_PREFIX = T.let("copilot.dev.spending_override.".freeze, String)

    sig { params(client: ::Billing::Platform::Api::Client, copilot_user: Copilot::User).returns(T.nilable(SpendingInfo)) }
    def self.fetch_copilot_spending_info(client:, copilot_user:)
      if Rails.env.development? && (dev_override = dev_spending_info_override(copilot_user))
        return dev_override
      end

      return nil unless copilot_user.has_cfi_access?

      user = copilot_user.user_object
      customer = user.customer
      return nil unless customer

      trust_tier = TrustTiers::Tier.for_billable_owner(user).tier
      copilot_plan = Copilot::CfiPlanResolver.resolve(copilot_user)
      return nil unless copilot_plan

      entity_detail = BillingPlatform::Base::EntityDetail.new(
        customerId: customer.id.to_s,
        copilotPlan: copilot_plan,
      )

      now = Time.now.utc
      response = client.get_spending_info(
        customer_id: customer.id,
        product: "copilot",
        entity_detail: entity_detail,
        trust_tier: trust_tier,
        year: now.year,
        month: now.month,
      )

      if response.is_a?(::Billing::Platform::Api::Error)
        Failbot.report(response,
          "gh.billing.customer.id" => customer.id,
          "code.namespace" => "Copilot::QuotaDataHelper",
          "code.function" => "fetch_copilot_spending_info",
        )
        return nil
      end

      {
        status: response[:status],
        overage_amount: response[:overageAmount].to_f,
        limit: response[:limit].to_f,
        limit_reached: response[:limitReached] == true,
        updated_at: response[:updatedAt].to_i,
      }
    rescue StandardError => e
      Failbot.report(e,
        "gh.billing.customer.id" => customer&.id,
        "code.namespace" => "Copilot::QuotaDataHelper",
        "code.function" => "fetch_copilot_spending_info",
      )
      nil
    end

    # Returns a synthetic SpendingInfo built from a dev-seeded overage value, or nil when
    # no override has been seeded for the user. Development only.
    sig { params(copilot_user: Copilot::User).returns(T.nilable(SpendingInfo)) }
    def self.dev_spending_info_override(copilot_user)
      return nil unless Rails.env.development?

      user = copilot_user.user_object
      # Dev-only testing seam (see script/setup-copilot-user); the global KV is acceptable here.
      raw = GitHub.kv.get("#{DEV_SPENDING_OVERRIDE_KV_PREFIX}#{user.id}").value { nil } # rubocop:disable GitHub/DoNotUseGlobalKv
      return nil if raw.nil?

      overage = raw.to_f
      {
        status: :SPENDING_STATUS_OK,
        overage_amount: overage,
        limit: 0.0,
        limit_reached: overage > 0.0,
        updated_at: Time.now.utc.to_i,
      }
    rescue StandardError
      nil
    end
    private_class_method :dev_spending_info_override
  end
end
