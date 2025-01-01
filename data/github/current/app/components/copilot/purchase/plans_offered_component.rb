# typed: strict
# frozen_string_literal: true

module Copilot
  module Purchase
    class PlansOfferedComponent < ApplicationComponent

      sig { returns(T.any(::Organization, ::Business)) }
      attr_reader :selected_account

      sig { params(selected_account: T.any(::Organization, ::Business)).void }
      def initialize(selected_account:)
        @selected_account = selected_account
      end

      private

      sig { returns(T::Boolean) }
      def is_business?
        selected_account.is_a? ::Business
      end

      sig { returns(T::Boolean) }
      def is_standalone_business?
        is_business? && T.cast(selected_account, ::Business).copilot_licensing_enabled?
      end

      sig { returns(String) }
      def heading
        is_business? ? "Copilot plans" : "Copilot plan"
      end
    end
  end
end
