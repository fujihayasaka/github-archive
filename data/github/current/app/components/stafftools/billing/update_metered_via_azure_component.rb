# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class UpdateMeteredViaAzureComponent < ApplicationComponent
      def initialize(user:, customer:)
        @user = user
        @customer = customer
      end

      def metered_via_azure?
        customer&.metered_via_azure? || false
      end

      def azure_subscription_id
        customer&.azure_subscription_id
      end

      private

      def render?
        user.organization?
      end

      attr_reader :user, :customer
    end
  end
end
