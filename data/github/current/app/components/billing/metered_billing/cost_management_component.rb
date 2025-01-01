# typed: true
# frozen_string_literal: true

module Billing
  module MeteredBilling
    class CostManagementComponent < ApplicationComponent
      attr_reader :budget_group, :title, :enforce_spending_limit, :spending_limit_in_subunits, :form_action, :product_name,
        :notification_form_action, :included_usage_notification, :paid_usage_notification, :billing_target

      def initialize(
        budget_group:,
        title: "",
        product_name: title,
        billing_target: nil,
        form_action: "",
        enforce_spending_limit: true,
        spending_limit_in_subunits: 0,
        disabled: false,
        notification_form_action: "",
        included_usage_notification: true,
        paid_usage_notification: true,
        has_products_with_included_usage: true
      )
        @budget_group = budget_group
        @title = title
        @product_name = product_name
        @disabled = disabled
        @billing_target = billing_target
        @form_action = form_action
        @enforce_spending_limit = enforce_spending_limit
        @spending_limit_in_subunits = spending_limit_in_subunits
        @notification_form_action = notification_form_action
        @included_usage_notification = included_usage_notification
        @paid_usage_notification = paid_usage_notification
        @has_products_with_included_usage = has_products_with_included_usage
      end

      def spending_limit_value
        number_with_precision(spending_limit_in_subunits / 100.0, precision: 2)
      end

      def disabled?
        @disabled
      end

      def disabled_attribute
        disabled? ? "disabled" : ""
      end

      def has_products_with_included_usage?
        @has_products_with_included_usage
      end

      def zero_limit_for_no_included_usage?
        !has_products_with_included_usage? && spending_limit_in_subunits.zero?
      end

      def zero_limit_for_no_included_usage_warning
        target_type = case billing_target
        when ::Business
          "your enterprise"
        when ::Organization
          "your organization"
        else
          "you"
        end

        "A $0 limit will prevent #{target_type} from using #{product_name}"
      end
    end
  end
end
