# typed: strict
# frozen_string_literal: true

module Codespaces
  module OrgEnablement
    class SetSpendingLimitBannerComponent < ApplicationComponent
      include BillingSettingsHelper

      sig { returns(::Business) }
      attr_reader :business

      sig { params(business: ::Business).void }
      def initialize(business:)
        @business = business
      end

      sig { returns(T::Boolean) }
      def render?
        # don't show anything to do with payment if free codespace use is enabled
        return false if business.free_codespace_use_enabled?
        return false if business.feature_enabled?(:codespaces_v_next_fix_budget_calls) && business.billing_v_next_enabled_for_codespaces?

        !billable? || !has_spending_limit?
      rescue ::Billing::Api::ClientWrapper::BillingClientError
        false
      end

      private

      sig { returns(T::Boolean) }
      memoize def billable?
        Codespaces::BillingPolicy.billable?(business)
      end

      sig { returns(::Billing::Budget) }
      def budget
        business.billable_owner.budget_for(group: "codespaces")
      end

      sig { returns(T::Boolean) }
      def has_spending_limit?
        usage = ::Billing::CodespacesUsage.new(account: business)
        usage.has_spending_limit_set?
      end
    end
  end
end
