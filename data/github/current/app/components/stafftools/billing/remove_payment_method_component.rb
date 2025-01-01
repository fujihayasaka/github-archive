# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class RemovePaymentMethodComponent < ApplicationComponent
      # user - a User or Organization
      def initialize(user:)
        @user = user
      end

      private

      attr_reader :user

      def render?
        user.has_valid_payment_method?
      end
    end
  end
end
