# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class BudgetNotification
      include GitHub::Memoizer

      attr_reader :result, :owner, :billable_owner, :budget, :context, :actor, :is_license_budget

      sig do
        params(
          budget: Billing::Platform::Api::Budget,
          is_license_budget: T.nilable(T::Boolean),
          context: T.nilable(T.any(User, Organization, Business, Repository)),
          actor: T.nilable(User)
        ).void
      end
      def initialize(budget:, is_license_budget: false, context: nil, actor: nil)
        @budget = budget
        @owner = budget.owner
        @context = context || owner
        @billable_owner = owner&.billable_owner
        @actor = actor
        @is_license_budget = is_license_budget
        @result = threshold_result
      end

      sig { returns(T.nilable(Billing::Notifications::BudgetNotificationSerializer)) }
      memoize def serialize
        return nil unless has_result?

        BudgetNotificationSerializer.new(self)
      end

      alias_method :highest_priority_notification, :serialize

      sig { returns(T::Boolean) }
      def has_result?
        result.present?
      end

      sig { returns(Billing::Platform::Api::Budget) }
      def active_budget
        budget
      end

      private

      GHAS_PRICING_TARGETS = T.let(%w[ghas_licenses ghas_code_security_licenses ghas_secret_protection_licenses].freeze, T::Array[String])

      sig { returns(T.nilable(Billing::Notifications::Result)) }
      def threshold_result
        return unless budget.owner.present?
        return unless budget.visible_to?(context)
        return unless budget.current_amount.positive?
        return unless budget.alert_enabled?
        return unless budget.threshold_alertable?
        return if billable_owner.plan.legacy?
        # Skip 100% threshold emails for GHAS hard budgets. There's a GHAS lock email that already includes budget context
        return if budget.threshold_percentage == 100 &&
          budget.fully_funded? && budget.budget_limit_type == "PreventFurtherUsage" &&
          GHAS_PRICING_TARGETS.include?(budget.pricing_target_id)

        # Skip notification if budget month/year is in the past (usage has been reset)
        if FeatureFlag.vexi.enabled?(:billing_budget_threshold_notification_month_year_fields, owner, default: false)
          if budget.month.present? && budget.year.present?
            begin
              # Validate that month and year are valid integers within valid ranges
              month = budget.month.to_i
              year = budget.year.to_i

              # Check if month and year are in valid ranges
              if month >= 1 && month <= 12 && year > 0
                budget_date = Date.new(year, month, 1)
                current_date = Date.current.beginning_of_month

                if budget_date < current_date
                  GitHub.logger.info(
                    "Skipping budget threshold notification for past period",
                    {
                      "gh.billing.budget.slug": budget.slug,
                      "gh.billing.budget.month": budget.month,
                      "gh.billing.budget.year": budget.year,
                      "gh.billing.current_month": current_date.month,
                      "gh.billing.current_year": current_date.year,
                      "gh.billing.customer.id": billable_owner.customer.id,
                    }
                  )
                  return
                end
              else
                # Log invalid month/year values but continue with notification processing
                GitHub.logger.warn(
                  "Invalid month/year values in budget, continuing with notification processing",
                  {
                    "gh.billing.budget.slug": budget.slug,
                    "gh.billing.budget.month": budget.month,
                    "gh.billing.budget.year": budget.year,
                    "gh.billing.customer.id": billable_owner.customer.id,
                  }
                )
              end
            rescue Date::Error, ArgumentError => e
              # Log the error but continue with notification processing
              GitHub.logger.warn(
                "Failed to parse budget month/year, continuing with notification processing",
                {
                  :"gh.billing.budget.slug" => budget.slug,
                  :"gh.billing.budget.month" => budget.month,
                  :"gh.billing.budget.year" => budget.year,
                  :"gh.billing.customer.id" => billable_owner.customer.id,
                  "error" => e.message,
                }
              )
            end
          end
        end

        context_data = {
          used: budget.current_amount,
          available: budget.target_amount,
          is_license_budget: is_license_budget,
          budget_state_quantity: convert_quantity(quantity: budget.quantity),
        }

        if is_license_budget
          context_data[:license_count] = budget.license_count
          context_data[:current_license_count] = budget.current_license_count
        end

        # Only include month/year if feature flag is enabled
        if FeatureFlag.vexi.enabled?(:billing_budget_threshold_notification_month_year_fields, owner, default: false)
          context_data[:month] = budget.month
          context_data[:year] = budget.year
        end

        Result.new(
          value: budget.current_percentage,
          threshold: budget.threshold_percentage,
          tags: [budget.product_name, budget.pricing_target_type, budget.budget_limit_type],
          context: context_data
        )
      end

      def convert_quantity(quantity:)
        quantity / (10**9)
      end
    end
  end
end
