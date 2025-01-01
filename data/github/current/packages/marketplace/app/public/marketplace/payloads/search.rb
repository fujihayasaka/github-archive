# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    class Search
      extend T::Sig
      extend T::Helpers
      include GitHub::Memoizer
      include MarketplaceHelper
      include Marketplace::Payloads::IndexHelper

      sig { override.returns(T.nilable(User)) }
      attr_reader :current_user
      sig { override.returns(ActionController::Parameters) }
      attr_reader :params

      sig { params(current_user: T.nilable(User), params: ActionController::Parameters).void }
      def initialize(current_user:, params:)
        @current_user = current_user
        @params = params
      end

      sig { returns(Marketplace::Types::Search) }
      def call
        {
          results: search_results_listings[:results].map { |result_view| listing_from_result_view(result_view) }.compact,
          total: search_results_listings[:total],
          # Clamp the total pages to the maximum results returned by Elasticsearch - https://github.com/github/copilot-extensibility/issues/358
          totalPages: [(search_results_listings[:total].to_f / PER_PAGE).ceil, (::Search::Query::MAX_RESULT_WINDOW / PER_PAGE).floor].min
        }
      end

      private

      sig { returns(SearchResults) }
      memoize def search_results_listings
        return null_search_results unless searching?

        search_query = params[:query] || ""

        normalized_verification_state = Marketplace::SearchOptions.find_normalized_verification_state(params[:verification])

        parsed_query = ::Search::Queries::MarketplaceQuery.normalize(
          ::Search::Queries::MarketplaceQuery.parse(params[:query]),
        )
        parsed_query.select { |(k, _v)| k == :sort }.map do |(k, v)|
          if MarketplaceHelper::SORT_VALUE_TO_LABEL[v] == nil?
            parsed_query.delete_if { |key, _value| key == k }
            break
          end
        end
        parsed_query = parsed_query.push([:sort, "popularity-desc"]) if parsed_query.select { |(k, _v)| k == :sort }.empty?

        search_query = ::Search::Queries::MarketplaceQuery.stringify(parsed_query)

        result_count = 0
        data = []

        variables = {
          searchQuery: map_keywords(search_query.to_s),
          verificationState: normalized_verification_state,
          categorySlug: params[:category].to_s,
          searchType: params[:type].to_s,
          modelTask: params[:task].to_s,
          modelFamily: params[:model_family].to_s,
          copilotApp: copilot_app_request?,
          items_per_page: PER_PAGE,
        }

        query = async_formulate_query?(variables).sync

        execute_query(query)
      end

      sig { params(query: String).returns(String) }
      def map_keywords(query)
        ::Search::Queries::MarketplaceQuery::KEYWORD_MAPPINGS.each { |k, v| query = query.gsub(k, v) }
        query
      end

      sig { returns(SearchResults) }
      def null_search_results
        {
          results: [],
          total: 0
        }
      end
    end
  end
end
