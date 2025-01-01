# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    class Search
      extend T::Helpers
      include GitHub::Memoizer
      include MarketplaceHelper
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

      sig { returns(Marketplace::Types::Search) }
      def call
        {
          results: search_results_listings[:results].map { |result_view| listing_from_result_view(result_view) }.compact,
          total: search_results_listings[:total],
          # Clamp the total pages to the maximum results returned by Elasticsearch - https://github.com/github/copilot-extensibility/issues/358
          totalPages: [(search_results_listings[:total].to_f / PER_PAGE).ceil, (::Search::Query::max_offset_window_default / PER_PAGE).floor].min,
          parsedQuery: parsed_query,
        }
      end

      private

      # Private: Returns the parsed query string.
      #
      # Example: for query string 'provider:"mistral ai",meta foo category:meta category:microsoft',
      # the parsed query is:
      #     [[:provider, "mistral ai,meta"], "foo", [:category, "meta"], [:category, "microsoft"]]
      sig { returns T::Array[T.untyped] }
      memoize def parsed_query
        result = ::Search::Queries::MarketplaceQuery.normalize(
          ::Search::Queries::MarketplaceQuery.parse(params[:query]),
        )
        result.select { |(k, _v)| k == :sort }.map do |(k, v)|
          if MarketplaceHelper::SORT_VALUE_TO_LABEL[v] == nil?
            result.delete_if { |key, _value| key == k }
            break
          end
        end
        if result.select { |(k, _v)| k == :sort }.empty?
          default_sort_value_for_type = if params[:type] == "models"
            MarketplaceHelper::DEFAULT_MODELS_SORT_VALUE
          else
            MarketplaceHelper::DEFAULT_SORT_VALUE
          end
          result = result.push([:sort, default_sort_value_for_type])
        end
        result
      end

      sig { returns(SearchResults) }
      memoize def search_results_listings
        return null_search_results unless searching?

        search_query = params[:query] || ""
        normalized_verification_state = Marketplace::SearchOptions.find_normalized_verification_state(params[:verification])
        search_query = ::Search::Queries::MarketplaceQuery.stringify(parsed_query)
        result_count = 0
        data = []

        variables = {
          searchQuery: map_keywords(search_query.to_s),
          verificationState: normalized_verification_state,
          categorySlug: params[:category].to_s,
          searchType: params[:type].to_s,
          modelTask: params[:task].to_s,
          publisher: params[:publisher].to_s,
          copilotApp: copilot_app_request?,
          items_per_page: PER_PAGE,
        }

        query = async_formulate_query?(variables).sync

        execute_query(query)
      end

      sig { params(query: String).returns(String) }
      def map_keywords(query)
        mappings = if params[:type] == "models"
          ::Search::Queries::MarketplaceQuery::MODELS_KEYWORD_MAPPINGS
        else
          ::Search::Queries::MarketplaceQuery::KEYWORD_MAPPINGS
        end
        mappings.each { |k, v| query = query.gsub(k, v) }
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
