# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    module IndexHelper
      extend T::Helpers
      include GitHub::Memoizer
      include MarketplaceHelper
      include Platform::Helpers::MarketplaceSearchHelper

      abstract!

      PER_PAGE = 20
      APP_TYPE = "MARKETPLACE"
      ACTION_TYPE = "MARKETPLACE_ACTIONS"
      ALL_TYPES = "MARKETPLACE_TOOLS"
      MODEL_TYPE = "AZURE_MODELS"

      # Keep in sync with SearchResults in ui/packages/marketplace-common/types.ts
      SearchResults = T.type_alias do
        {
          results: T::Array[::Search::MarketplaceListingResultView],
          total: Integer
        }
      end

      sig { abstract.returns(T.nilable(User)) }
      def current_user; end

      sig { abstract.returns(ActionController::Parameters) }
      def params; end

      sig { abstract.returns(T.nilable(T::Boolean)) }
      def is_eu_request; end

      private

      sig { params(search_query: String).returns(SearchResults) }
      def execute_query(search_query)
        variables = {
          searchQuery: search_query,
          copilotApp: copilot_app_request?,
          verificationState: params[:verification],
          items_per_page: PER_PAGE,
          searchType: search_type,
          isDsaCompliant: dsa_compliance_required?,
        }

        case params[:filter]
        when "free_trial"
          variables[:withFreeTrialsOnly] = true
        when "enterprise"
          variables[:enterpriseCompatibleOnly] = true
        end

        result = get_execute_query(search_query, variables, page).execute
        if result != nil && result.total > 0
          {
            results: result.results,
            total: result.total
          }
        else
          {
            results: [],
            total: 0
          }
        end
      end

      sig { returns(Integer) }
      memoize def page
        (params[:page] || 1).to_i
      end

      sig { returns(T.nilable(T::Boolean)) }
      memoize def copilot_app_request?
        ActiveModel::Type::Boolean.new.cast(params[:copilot_app])
      end

      sig { returns(T::Boolean) }
      memoize def searching?
        params[:query].present? ||
          params[:category].present? ||
          params[:type].present? ||
          params[:copilot_app].present?
      end

      sig { returns(String) }
      def search_type
        case params[:type]
        when "actions"
          ::Search::Queries::MarketplaceQuery::SEARCH_TYPES[ACTION_TYPE]
        when "apps"
          ::Search::Queries::MarketplaceQuery::SEARCH_TYPES[APP_TYPE]
        when "models"
          ::Search::Queries::MarketplaceQuery::SEARCH_TYPES[MODEL_TYPE]
        else
          ::Search::Queries::MarketplaceQuery::SEARCH_TYPES[ALL_TYPES]
        end
      end

      sig do
        params(result_view: T.any(::Search::MarketplaceListingResultView,
                                  ::Search::RepositoryActionResultView,
                                  ::Search::AzureModelResultView))
          .returns(Marketplace::Types::ListingPreview)
      end
      def listing_from_result_view(result_view)
        if result_view.is_a?(::Search::MarketplaceListingResultView)
          Marketplace::Serializers::App.serialize_search_view(result_view)
        elsif result_view.is_a?(::Search::RepositoryActionResultView)
          Marketplace::Serializers::Action.serialize_search_view(result_view)
        else
          result_view.for_frontend_rendering
        end
      end

      sig { returns(T::Boolean) }
      memoize def dsa_compliance_required?
        flag = :hide_noncompliant_marketplace_listings_in_eu
        return false unless current_user&.feature_enabled?(flag) || GitHub.flipper[flag].enabled?

        ActiveModel::Type::Boolean.new.cast(is_eu_request)
      end
    end
  end
end
