# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class BillingBudgetStateBannerComponent < ApplicationComponent
      attr_reader :message, :type

      def initialize(message:, type:)
        @message = message
        @type = type
      end
    end
  end
end
