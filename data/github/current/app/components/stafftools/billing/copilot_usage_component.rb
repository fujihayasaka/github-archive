# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class CopilotUsageComponent < ApplicationComponent
      attr_reader :copilot_monthly_usage, :user

      def initialize(
        user:,
        copilot_monthly_usage:
      )
        @user = user
        @copilot_monthly_usage = copilot_monthly_usage
      end

      def render?
        copilot_monthly_usage.present? &&
          user.plan.copilot_for_biz_eligible? &&
          ::Copilot.copilot_object(user).copilot_for_business_enabled?
      end

      def total_usage
        copilot_monthly_usage.meuse_product_usage
      end

      def total_cost
        ::Billing::Money.new(copilot_monthly_usage.meuse_product_cost).format(no_cents_if_whole: false)
      end
    end
  end
end
