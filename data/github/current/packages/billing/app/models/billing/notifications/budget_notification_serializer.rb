# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class BudgetNotificationSerializer
      include UrlHelpers
      include ActionView::Helpers::NumberHelper
      include ActionView::Helpers::UrlHelper

      attr_reader :budget_notification

      delegate :owner, :billable_owner, :context, :actor, :budget, :result, to: :budget_notification

      class ProductEnum < T::Enum
        enums do
          Actions = new
          Codespaces = new
          Copilot = new
          Ghas = new
          Ghec = new
          Git_Lfs = new
          Packages = new
        end
      end

      sig { params(budget_notification: Billing::Notifications::BudgetNotification).void }
      def initialize(budget_notification)
        @budget_notification = budget_notification
      end

      sig { returns(String) }
      def text
        if budget.target.is_a?(Repository)
          "You've used #{result.threshold}% of your #{metered_service_name} budget for the #{budget.target_name} repo."
        elsif budget.target.is_a?(Organization)
          "You've used #{result.threshold}% of your #{metered_service_name} budget for the #{budget.target_name} org."
        elsif budget.target.is_a?(Billing::Platform::Api::CostCenter)
          "You've used #{result.threshold}% of your #{metered_service_name} budget for the #{budget.target_name} cost center."
        elsif owner.is_a?(Organization) || context.is_a?(Repository)
          "Your enterprise has used #{result.threshold}% of its budget for #{metered_service_name}."
        else
          "You've used #{result.threshold}% of your #{metered_service_name} Enterprise budget."
        end
      end

      sig { returns(String) }
      def usage_reset_date_text
        "Your usage will reset on #{owner.billable_owner.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}"
      end

      sig { returns(String) }
      def metered_service_name
        case budget.pricing_target_id
        when ProductEnum::Actions.serialize
          "Actions"
        when ProductEnum::Codespaces.serialize
          "Codespaces"
        when ProductEnum::Copilot.serialize
          "Copilot"
        when ProductEnum::Ghas.serialize
          "GitHub Advanced Security"
        when ProductEnum::Ghec.serialize
          "GitHub Enterprise Cloud"
        when ProductEnum::Git_Lfs.serialize
          "Git LFS"
        when ProductEnum::Packages.serialize
          "Packages"
        else
          "metered services"
        end
      end

      sig { returns(Integer) }
      def threshold
        result.threshold
      end

      sig { returns(String) }
      def mail_subject
        "You've hit #{result.threshold}% of your budget"
      end

      sig { returns(String) }
      def mail_icon
        "cogs.png"
      end

      sig { returns(String) }
      def mail_product_title
        "Budget usage"
      end

      sig { returns(String) }
      def progress_bar_title
        "Budget"
      end

      sig { returns(String) }
      def progress_bar_details_text
        context = result.context

        used = number_to_currency(context[:used])
        available = number_to_currency(context[:available])

        "#{used} of #{available}"
      end

      sig { returns(String) }
      def slack_notification_message
        "used #{result.value}% of paid usage services"
      end

      sig { returns(T::Array[String]) }
      def filtered_by_tags
        result.tags
      end

      sig { returns(T::Array[String]) }
      def product_tags
        [budget.product_name]
      end

      sig { returns(T.nilable(Float)) }
      def meter_available
        context = result.context
        return unless context.present?

        result.context[:available]
      end

      sig { returns(Symbol) }
      def variant
        return :danger if budget.fully_funded?

        :warning
      end

      sig { returns(T::Boolean) }
      def is_actor_enterprise_owner?
        return false unless actor.present?

        business = owner.billable_owner
        business.owners.include?(actor)
      end
    end
  end
end
