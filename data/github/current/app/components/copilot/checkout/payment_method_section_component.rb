# typed: strict
# frozen_string_literal: true

module Copilot
  module Checkout
    class PaymentMethodSectionComponent < ApplicationComponent
      sig { params(user: ::User, return_to_path: String).void }
      def initialize(user:, return_to_path:)
        @user = user
        @return_to_path = return_to_path
      end

      sig { returns(T::Boolean) }
      def render?
        !!(GitHub.billing_enabled? &&
          !helpers.has_billing_info_validation_error?(user) &&
          !user.has_commercial_interaction_restriction?(feature_type: :copilot) &&
          user.has_saved_billing_information?)
      end

      private

      sig { returns(::User) }
      attr_reader :user

      sig { returns(String) }
      attr_reader :return_to_path
    end
  end
end
