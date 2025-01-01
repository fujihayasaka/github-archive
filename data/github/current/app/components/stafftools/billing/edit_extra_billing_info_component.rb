# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class EditExtraBillingInfoComponent < ApplicationComponent
      def initialize(user:)
        @user = user
      end

      private

      attr_reader :user
    end
  end
end
