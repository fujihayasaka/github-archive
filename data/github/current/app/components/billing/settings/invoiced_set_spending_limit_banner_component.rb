# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class InvoicedSetSpendingLimitBannerComponent < ApplicationComponent
      attr_reader :spending_limit_path, :dismissal_path

      def initialize(spending_limit_path:, dismissal_path:)
        @spending_limit_path = spending_limit_path
        @dismissal_path = dismissal_path
      end
    end
  end
end
