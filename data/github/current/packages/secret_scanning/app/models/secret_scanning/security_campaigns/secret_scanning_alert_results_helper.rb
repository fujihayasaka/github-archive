# sorbet/rbi/shims/repository_common_relation_methods.rbi
# typed: strict
# frozen_string_literal: true

# This file mostly follows the pattern set for Code Scanning Campaigns in SecurityCampaigns::AlertResultsHelper
module SecretScanning
  module SecurityCampaigns
    module SecretScanningAlertResultsHelper
      include GitHub::Memoizer
      include Orgs::SecurityCenter::SecretScanningOrgQueriesHelper

      # Retrieve the maximum number of alert results from Token Scanning Service.
      # @return [T::Hash[Integer, T::Array[GitHub::TokenScanning::Service::Token]], Boolean]
      #   T::Hash[Integer, T::Array[GitHub::TokenScanning::Service::Token]] The alert results grouped by repository ID
      #   Boolean true if there was a backend error, false for success
      sig { params(query: Search::Queries::SecurityCenter::SecretScanningQuery).returns([T::Hash[Integer, T::Array[GitHub::TokenScanning::Service::Token]], T::Boolean]) }
      def secret_scanning_alerts_from_query(query)
        _ = T.let(nil, T.untyped)
        repository_ids, _ = allowed_repository_ids_by_feature_for_organization_members[SecurityCenter::SecurityFeatures::SECRET_SCANNING]
        alert_results_by_repository_id = T.let({}, T::Hash[Integer, T::Array[GitHub::TokenScanning::Service::Token]])
        return [{}, false] if repository_ids&.empty?

        alert_query_service = SecretScanning::AlertQueryService.for_organization(
          organization: this_organization,
          current_user:,
          user_session:,
          allowed_repository_ids: repository_ids,
          query: query_string,
        )

        cursor = T.let(nil, T.nilable(String))

        max_requests = 15
        requests = 0

        alert_results = T.let([], T::Array[GitHub::TokenScanning::Service::Token])
        while alert_results.size < ::SecurityCampaigns::MAX_ALERTS_COUNT && requests < max_requests
          page_alert_results, _, _, response, request_error = alert_query_service.get_alerts_with_response(
            after_cursor: cursor,
            per_page: 100,
          )

          if request_error
            return [{}, true]
          end

          cursor = response.try(:data).try(:next_cursor)
          page_alert_results.each do |alert|
            alert_results << alert
            break if alert_results.size >= ::SecurityCampaigns::MAX_ALERTS_COUNT
          end
          break if cursor.blank?

          requests += 1
        end

        alert_results.each do |alert|
          unless alert_results_by_repository_id.key?(alert.repository_id)
            alert_results_by_repository_id[alert.repository_id] = []
          end

          T.must(alert_results_by_repository_id[alert.repository_id]) << alert
        end

        [alert_results_by_repository_id, false]
      end

      private

      sig { returns(String) }
      memoize def query_string
        params[:query]&.strip || "is:open"
      end
    end
  end
end
