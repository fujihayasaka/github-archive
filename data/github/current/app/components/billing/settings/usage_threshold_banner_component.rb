# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class UsageThresholdBannerComponent < ApplicationComponent
      attr_reader :is_dismiss_enabled, :variant, :title_text, :body_text, :has_dismissed_notice, :spending_limit_path, :dismissal_path, :show_update_spending_limit, :use_budgets

      def initialize(is_dismiss_enabled:, variant:, title_text:, body_text:, has_dismissed_notice:, spending_limit_path:, dismissal_path:, show_update_spending_limit:, is_trade_restricted:, use_budgets: false)
        @is_dismiss_enabled = is_dismiss_enabled
        @variant = variant
        @title_text = title_text
        @body_text = body_text
        @has_dismissed_notice = has_dismissed_notice
        @spending_limit_path = spending_limit_path
        @dismissal_path = dismissal_path
        @show_update_spending_limit = show_update_spending_limit
        @is_trade_restricted = is_trade_restricted
        @use_budgets = use_budgets
      end

      def render?
        !has_dismissed_notice && variant_set?
      end

      def show_dismiss_form?
        is_dismiss_enabled && !danger_variant?
      end

      def show_update_spending_limit?
        show_update_spending_limit && !is_trade_restricted?
      end

      def is_trade_restricted?
        @is_trade_restricted
      end

      def use_budgets?
        @use_budgets
      end

      private

      def danger_variant?
        variant == :danger
      end

      def variant_set?
        variant != :none
      end
    end
  end
end
