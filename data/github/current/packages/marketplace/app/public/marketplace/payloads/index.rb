# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    class Index
      extend T::Helpers
      include Marketplace::Payloads::IndexHelper
      include GitHubModels::PlaygroundDependency

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

      sig do
        returns({
          featured: T::Array[Marketplace::Types::ListingPreview],
          recommended: T::Array[Marketplace::Types::ListingPreview],
          recentlyAdded: T::Array[Marketplace::Types::ListingPreview],
          featuredModels: T::Array[GitHubModels::Types::FeaturedModel],
          recentModels: T::Array[GitHubModels::Types::FeaturedModel],
          popularModels: T::Array[GitHubModels::Types::FeaturedModel],
          searchResults: Marketplace::Types::Search,
          categories: {
            apps: T::Array[Marketplace::Types::SerializedCategory],
            actions: T::Array[Marketplace::Types::SerializedCategory],
          }
        })
      end
      def call
        recent_models = GitHubModels.domain.models.find_many(order: GitHubModels::ModelOrder::RecentlyAdded,
          publicly_visible_only: true, limit: 3)
        popular_models = GitHubModels.domain.models.find_many(order: GitHubModels::ModelOrder::Popular,
          publicly_visible_only: true, limit: 3)
        {
          featured: featured_listings.map { |result_view| listing_from_result_view(result_view) }.compact,
          recommended: recommended_listings.map { |result_view| listing_from_result_view(result_view) }.compact,
          recentlyAdded: recently_added_listings.map { |result_view| listing_from_result_view(result_view) }.compact,
          featuredModels: models_user.featured_models,
          recentModels: recent_models.map { |model| models_user.model_hash(model) },
          popularModels: popular_models.map { |model| models_user.model_hash(model) },
          searchResults: Marketplace::Payloads::Search.new(current_user: current_user, params: params, is_eu_request: is_eu_request).call,
          categories: Marketplace::Payloads::Categories.new.call
        }
      end

      private

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
          normalizer: normalizer,
          is_dsa_compliant: dsa_compliance_required?,
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
          normalizer: normalizer,
          is_dsa_compliant: dsa_compliance_required?,
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
