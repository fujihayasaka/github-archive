# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class CompletionStatusComponent < ApplicationComponent
      extend T::Sig

      include MarketplaceHelper

      sig { returns(String) }
      attr_reader :completion_path

      sig { returns(T::Boolean) }
      attr_reader :onboarding_status_logic

      sig { returns(String) }
      attr_reader :description

      sig { params(completion_path: String, onboarding_status_logic: T::Boolean, description: String).void }
      def initialize(completion_path:, onboarding_status_logic:, description:)
        @completion_path = completion_path
        @onboarding_status_logic = onboarding_status_logic
        @description = description
      end
    end
  end
end
