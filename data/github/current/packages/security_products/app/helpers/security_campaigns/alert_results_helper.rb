# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module AlertResultsHelper
    extend T::Sig

    include GitHub::Memoizer
    include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper

    # Retrieve the maximum number of alert results from Turboscan. We can't do this in 1 request because Turboscan has
    # a maximum page size of (currently) 100, while our (current) maximum is 500 alerts.
    # @return [Array<CodeScanning::AlertResult>, Boolean]
    #   Array<CodeScanning::AlertResult> The alert results that were retrieved.
    #   Boolean                          indicates backend error
    sig { params(query: Search::Queries::SecurityCenter::CodeScanningOrgQuery).returns([T::Array[CodeScanning::AlertResult], T::Boolean]) }
    def alert_results_from_query(query)
      tags = ["kind:turboscan_alerts"]
      GitHub.dogstats.distribution_time("security_campaigns.alerts_by_repo_load", tags: tags) do
        alert_results = T.let([], T::Array[CodeScanning::AlertResult])

        cursor = T.let(nil, T.nilable(String))

        # All alerts may be filtered out by the additonal check on repository visibility, so we need to ensure we don't
        # get stuck in an infinite loop.
        max_requests = 15
        requests = 0

        while alert_results.size < SecurityCampaigns::MAX_ALERTS_COUNT && requests < max_requests
          page_alert_results, _, has_error, response = alert_query_service.alerts_by_repo_with_response(
            after_cursor: cursor,
            # Always fetch the maximum number of alerts, unless we require fewer to reach the limit.
            per_page: [SecurityCampaigns::TURBOSCAN_MAX_PAGE_SIZE, SecurityCampaigns::MAX_ALERTS_COUNT - alert_results.size].min,
          )

          if has_error
            return [alert_results, true]
          end

          # Ensure only private repositories are included. This is an additional check because the Turboscan API
          # might be working with stale data.
          page_alert_results = page_alert_results.select do |alert|
            alert.repository.private?
          end

          alert_results += page_alert_results
          cursor = response.try(:data).try(:next_cursor)

          if cursor.blank?
            # If we receive an empty next cursor, there are no more results on the next pages.
            break
          end

          requests += 1
        end

        [alert_results, false]
      end
    end

    # Map a list of code scanning alert results to the hash that is expected by security campaigns. Will automatically
    # limit the number of alerts to MAX_ALERTS_COUNT and the number of repositories to MAX_ALERTS_REPOSITORY_COUNT.
    sig { params(alert_results: T::Array[CodeScanning::AlertResult]).returns(T::Hash[Integer, T::Array[Integer]]) }
    def security_campaigns_alerts_from_alert_results(alert_results)
      logical_alert_info = T.let({}, T::Hash[Integer, T::Array[Integer]])

      # If for some reason we have more results than the limit allows, we'll just take the first MAX_ALERTS_COUNT
      # results and ignore the rest.
      if alert_results.size > SecurityCampaigns::MAX_ALERTS_COUNT
        alert_results = alert_results.first(SecurityCampaigns::MAX_ALERTS_COUNT)
      end

      alert_results.each do |alert_result|
        if !logical_alert_info.key?(alert_result.repository.id)
          # If we have more repositories than the limit allows, we'll just ignore the rest.
          # However, we can't skip out of this loop because a repository that we already have alerts
          # for might be the next one in the list.
          if logical_alert_info.size >= SecurityCampaigns::MAX_ALERTS_REPOSITORY_COUNT
            next
          end

          logical_alert_info[alert_result.repository.id] = []
        end

        T.must(logical_alert_info[alert_result.repository.id]) << alert_result.result.number
      end

      logical_alert_info
    end

    # Override the alert_query_service to only include internal and private repositories.
    sig { returns(CodeScanning::AlertQueryService) }
    memoize def alert_query_service
      allowed_repo_ids, _ = allowed_repo_ids_and_limit_exceeded

      CodeScanning::AlertQueryService.for_organization(
        user: current_user,
        user_session: user_session,
        organization: this_organization,
        allowed_repository_ids: allowed_repo_ids,
        query: query_string,
        visibility: SecurityCampaigns::REPOSITORY_VISIBILITIES,
      )
    end
  end
end
