# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class UpdateAzureSubscriptionComponent < ApplicationComponent
      def initialize(user:, customer:)
        @user = user
        @customer = customer
      end

      def azure_subscription_id
        customer&.azure_subscription_id
      end

      private

      def render?
        user.organization? && user.invoiced?
      end

      attr_reader :user, :customer
    end
  end
end
