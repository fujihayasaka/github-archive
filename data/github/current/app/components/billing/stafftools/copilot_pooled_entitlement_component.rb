# typed: strict
# frozen_string_literal: true

module Billing
  module Stafftools
    class CopilotPooledEntitlementComponent < ApplicationComponent
      include Billing::TokenBasedBilling

      sig { returns(Billing::Types::OrgOrBusiness) }
      attr_reader :account

      sig { returns(T::Boolean) }
      attr_reader :is_business

      sig { returns(T.nilable(Integer)) }
      attr_reader :customer_id

      sig { params(account: Billing::Types::OrgOrBusiness, customer_id: T.nilable(Integer), is_business: T::Boolean).void }
      def initialize(account:, customer_id:, is_business:)
        @account = account
        @customer_id = customer_id
        @is_business = is_business
      end

      sig { returns(T::Boolean) }
      def render?
        billing_tbb_enabled?(account)
      end

      sig { returns(String) }
      def refresh_form_path
        if is_business
          helpers.refresh_pooled_entitlement_stafftools_enterprise_path(T.cast(account, Business))
        else
          helpers.refresh_pooled_entitlement_stafftools_user_path(T.cast(account, Organization))
        end
      end

      sig { returns(String) }
      def reset_current_amount_form_path
        if is_business
          helpers.reset_pooled_entitlement_stafftools_enterprise_path(T.cast(account, Business))
        else
          helpers.reset_pooled_entitlement_stafftools_user_path(T.cast(account, Organization))
        end
      end

      sig { returns(T::Boolean) }
      def error?
        pooled_entitlement_response.is_a?(Billing::Platform::Api::Error)
      end

      sig { returns(String) }
      def error_message
        if error?
          T.cast(pooled_entitlement_response, Billing::Platform::Api::Error).message
        else
          ""
        end
      end

      sig { returns(String) }
      def discount_target_amount
        data = response_data
        return "-" if data.nil?
        format_dollar(data[:discountTargetAmount])
      end

      sig { returns(String) }
      def discount_state_current_amount
        data = response_data
        return "-" if data.nil?
        format_dollar(data[:discountStateCurrentAmount])
      end

      sig { returns(String) }
      def discount_state_target_amount
        data = response_data
        return "-" if data.nil?
        format_dollar(data[:discountStateTargetAmount])
      end

      sig { returns(String) }
      def discount_state_fully_applied
        data = response_data
        return "-" if data.nil?
        data[:discountStateIsFullyApplied] ? "Yes" : "No"
      end

      private

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def response_data
        response = pooled_entitlement_response
        return nil if response.is_a?(Billing::Platform::Api::Error)
        response
      end

      sig { params(value: T.untyped).returns(String) }
      def format_dollar(value)
        "$#{"%.2f" % value.to_f}"
      end

      sig { returns(T.any(T::Hash[Symbol, T.untyped], Billing::Platform::Api::Error)) }
      memoize def pooled_entitlement_response
        if customer_id.nil?
          Billing::Platform::Api::Error.new("No customer ID found")
        else
          billing_client.admin_get_pooled_entitlement(customer_id: customer_id)
        end
      end

      sig { returns(::Billing::Platform::Api::Client) }
      memoize def billing_client
        ::Billing::Platform::Api::Client.new
      end
    end
  end
end
