# typed: strict
# frozen_string_literal: true

module Copilot
  module Checkout
    class BillingInfoSectionComponent < ApplicationComponent
      sig { params(user: ::User, return_to_path: String).void }
      def initialize(user:, return_to_path:)
        @user = user
        @return_to_path = return_to_path
      end

      private

      sig { returns(::User) }
      attr_reader :user

      sig { returns(String) }
      attr_reader :return_to_path

      sig { returns(T.untyped) }
      def billing_information
        user.billing_contact
      end

      sig { returns(T::Boolean) }
      def has_saved_billing_information?
        !!user.has_saved_billing_information?
      end

      sig { returns(T::Boolean) }
      def billing_info_present_without_errors?
        !!helpers.billing_info_exists_without_errors?(user)
      end

      sig { returns(T::Boolean) }
      def hide_billing_information_form?
        has_commercial_restrictions? || billing_info_present_without_errors?
      end

      sig { returns(T::Boolean) }
      def has_commercial_restrictions?
        !!user.has_commercial_interaction_restriction?(feature_type: :copilot)
      end
    end
  end
end
