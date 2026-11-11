# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class ByokFormComponent < ApplicationComponent
      include GitHub::Memoizer

      sig { returns(::Business) }
      attr_reader :business

      sig { params(business: ::Business, return_to: T.nilable(String), can_write: T::Boolean).void }
      def initialize(business:, return_to: nil, can_write: true)
        @business = business
        @return_to = return_to
        @can_write = can_write
      end

      private

      sig { returns(String) }
      def submit_path
        update_enablement_copilot_byok_custom_models_enterprise_path(business)
      end

      sig { returns(T.nilable(String)) }
      attr_reader :return_to

      sig { returns(T::Boolean) }
      attr_reader :can_write

      sig { returns(T::Boolean) }
      def enabled?
        business.copilot_custom_models_enabled?
      end
    end
  end
end
