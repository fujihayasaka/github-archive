# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class MeteredServiceLockFormComponent < ApplicationComponent
      attr_reader :account_type, :account_id, :is_locked

      def initialize(is_locked:, account_type:, account_id:)
        @is_locked = is_locked
        @account_type = account_type
        @account_id = account_id
      end

      private

      def form_method
        is_locked ? :delete : :post
      end

      def button_text
        is_locked ? "Unlock Metered Services" : "Lock Metered Services"
      end
    end
  end
end
