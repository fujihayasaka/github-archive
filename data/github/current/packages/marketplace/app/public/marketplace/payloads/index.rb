# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    class Index
      extend T::Sig
      extend T::Helpers
      include Marketplace::Payloads::IndexHelper
      include Marketplace::Models::PlaygroundDependency

      sig { override.returns(T.nilable(User)) }
      attr_reader :current_user
      sig { override.returns(ActionController::Parameters) }
      attr_reader :params

      sig { params(current_user: T.nilable(User), params: ActionController::Parameters).void }
      def initialize(current_user:, params:)
        @current_user = current_user
        @params = params
      end

      sig do
        returns({
          featured: T::Array[Marketplace::Types::Listing],
          recommended: T::Array[Marketplace::Types::Listing],
          recentlyAdded: T::Array[Marketplace::Types::Listing],
          featuredModels: T::Array[Marketplace::Types::AzureModels::Model],
          searchResults: Marketplace::Types::Search,
          categories: {
            apps: T::Array[Marketplace::Types::SerializedCategory],
            actions: T::Array[Marketplace::Types::SerializedCategory],
          }
        })
      end
      def call
        {
          featured: featured_listings.map { |result_view| listing_from_result_view(result_view) },
          recommended: recommended_listings.map { |result_view| listing_from_result_view(result_view) },
          recentlyAdded: recently_added_listings.map { |result_view| listing_from_result_view(result_view) },
          featuredModels: featured_models,
          searchResults: Marketplace::Payloads::Search.new(current_user: current_user, params: params).call,
          categories: Marketplace::Payloads::Categories.new.call
        }
      end

      private

      sig { returns(T::Array[Marketplace::Types::AzureModels::Model]) }
      def featured_models
        models.select { |model| FEATURED_MODEL_NAMES.include?(model[:name]) }
      end

      sig { returns(T::Array[::Search::MarketplaceListingResultView]) }
      def featured_listings
        return [] if searching?

        ::Search::Queries::MarketplaceQuery.new(
          current_user: current_user,
          phrase: "",
          sort: "last-month-popularity",
          type: ::Search::Queries::MarketplaceQuery::SEARCH_TYPES["MARKETPLACE"],
          offers_free_trial: nil,
          enterprise_compatible: nil,
          verification_state: nil,
          copilot_app: true,
          context: "marketplace-landing-page",
          highlight: ::Search::OffsetHighlighter.defaults,
          per_page: 6,
          normalizer: normalizer
        ).execute.results.first(6)
      end

      sig { returns(T::Array[::Search::MarketplaceListingResultView]) }
      def recommended_listings
        return [] if searching?

        ::Search::Queries::MarketplaceQuery.new(
          current_user: current_user,
          phrase: "",
          type: ::Search::Queries::MarketplaceQuery::SEARCH_TYPES["MARKETPLACE"],
          offers_free_trial: nil,
          enterprise_compatible: nil,
          verification_state: nil,
          copilot_app: false,
          context: "marketplace-landing-page",
          highlight: ::Search::OffsetHighlighter.defaults,
          per_page: PER_PAGE,
          normalizer: normalizer
        ).execute.results
      end

      sig { returns(T::Array[::Search::MarketplaceListingResultView]) }
      def recently_added_listings
        return [] if searching?

        execute_query("sort:created-desc")[:results]
      end

      sig { returns(T.proc.params(arg0: T.untyped).returns(T.untyped)) }  # rubocop:disable Sorbet/ForbidTUntyped
      def normalizer
        lambda do |results|
          results.map! do |h|
            case h["_source"]["search_type"]
            when "marketplace_listing"
              ::Search::MarketplaceListingResultView.new(h)
            when "repository_action"
              ::Search::RepositoryActionResultView.new(h)
            end
          end
        end
      end
    end
  end
end
