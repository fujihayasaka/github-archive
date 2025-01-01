# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class MeteredUsageComponent < ApplicationComponent
      attr_reader :manage_spending_limit_href, :metered_service_total_cents, :standalone_enterprise_enabled, :ghe_spending_limits_enabled, :has_error

      def initialize(manage_spending_limit_href:, metered_service_total_cents:, standalone_enterprise_enabled: false, ghe_spending_limits_enabled: false, has_error: false)
        @has_error = has_error
        @manage_spending_limit_href = manage_spending_limit_href
        @metered_service_total_cents = metered_service_total_cents
        @ghe_spending_limits_enabled = ghe_spending_limits_enabled
        @standalone_enterprise_enabled = standalone_enterprise_enabled
      end

      def is_ghe_spending_limits_enabled?
        ghe_spending_limits_enabled
      end

      def metered_service_total_dollars
        ::Billing::Money.new(metered_service_total_cents).dollars
      end
    end
  end
end
