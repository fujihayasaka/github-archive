# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    class RecentlyAdded
      extend T::Helpers
      include Marketplace::Payloads::IndexHelper

      sig { override.returns(T.nilable(User)) }
      attr_reader :current_user
      sig { override.returns(ActionController::Parameters) }
      attr_reader :params
      sig { override.returns(T.nilable(T::Boolean)) }
      attr_reader :is_eu_request

      sig { params(current_user: T.nilable(User), params: ActionController::Parameters, is_eu_request: T.nilable(T::Boolean)).void }
      def initialize(current_user:, params:, is_eu_request:)
        @current_user = current_user
        @params = params
        @is_eu_request = is_eu_request
      end

      sig { returns(T::Array[Marketplace::Types::ListingPreview]) }
      def call
        recently_added_listings.map { |result_view| listing_from_result_view(result_view) }.compact
      end

      private

      sig { returns(T::Array[::Search::MarketplaceListingResultView]) }
      def recently_added_listings
        return [] if searching?

        execute_query("sort:created-desc")[:results]
      end
    end
  end
end
