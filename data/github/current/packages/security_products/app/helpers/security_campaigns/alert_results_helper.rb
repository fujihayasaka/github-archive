# sorbet/rbi/shims/repository_common_relation_methods.rbi
# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module AlertResultsHelper
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
        repository_ids = recently_pushed_to_repository_ids(query)
        alert_results = T.let([], T::Array[CodeScanning::AlertResult])
        return [alert_results, false] if repository_ids&.empty?

        alert_query_service = alert_query_service(repository_ids:)
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
    # limit the number of alerts to MAX_ALERTS_COUNT and the number of repositories to SecurityCampaigns#max_alerts_repository_count.
    sig { params(alert_results: T::Array[CodeScanning::AlertResult]).returns(T::Hash[Integer, T::Array[Turboscan::Proto::Result]]) }
    def security_campaigns_alerts_from_alert_results(alert_results)
      logical_alert_info = T.let({}, T::Hash[Integer, T::Array[Turboscan::Proto::Result]])

      # If for some reason we have more results than the limit allows, we'll just take the first MAX_ALERTS_COUNT
      # results and ignore the rest.
      if alert_results.size > SecurityCampaigns::MAX_ALERTS_COUNT
        alert_results = alert_results.first(SecurityCampaigns::MAX_ALERTS_COUNT)
      end

      alert_results.each do |alert_result|
        if !logical_alert_info.key?(T.must(alert_result.repository.id))
          # If we have more repositories than the limit allows, we'll just ignore the rest.
          # However, we can't skip out of this loop because a repository that we already have alerts
          # for might be the next one in the list.
          if logical_alert_info.size >= SecurityCampaigns.max_alerts_repository_count(this_organization)
            next
          end

          logical_alert_info[T.must(alert_result.repository.id)] = []
        end

        T.must(logical_alert_info[T.must(alert_result.repository.id)]) << alert_result.result
      end

      logical_alert_info
    end

    # Override the alert_query_service to only include internal and private repositories.
    sig { params(repository_ids: T.nilable(T::Array[Integer])).returns(CodeScanning::AlertQueryService) }
    def alert_query_service(repository_ids: nil)
      allowed_repo_ids, _ = allowed_repo_ids_and_limit_exceeded

      if allowed_repo_ids.nil?
        allowed_repo_ids = repository_ids
      elsif !repository_ids.nil?
        allowed_repo_ids &= repository_ids
      end

      CodeScanning::AlertQueryService.for_organization(
        user: current_user,
        user_session: user_session,
        organization: this_organization,
        allowed_repository_ids: allowed_repo_ids,
        query: query_string,
      )
    end

    private

    ## Generate a list of repository ids that have been pushed to recently and have alerts up to the limit
    sig { params(query: Search::Queries::SecurityCenter::CodeScanningOrgQuery).returns(T.nilable(T::Array[Integer])) }
    def recently_pushed_to_repository_ids(query)
      repository_ids_and_alert_counts = alert_query_service.repository_ids_from_filters

      return [] if repository_ids_and_alert_counts.empty?

      alert_count_by_repo_id = repository_ids_and_alert_counts.each_with_object({}) do |repo, hash|
        next if repo.alert_count.zero?

        hash[repo.repository_id] = repo.alert_count
      end

      sorted_repos = Repository.where(organization: this_organization, id: alert_count_by_repo_id.keys)

      alerts_count = 0
      repository_ids = T::Array[Integer].new

      ## the .order is for ordering each batches otherwise each batch will be ordered by id.
      sorted_repos.order(pushed_at: :desc).in_batches(cursor: [:pushed_at, :id], order: :desc, of: 1000) do |batch|
        batch.pluck(:id).each do |repo_id|
          return repository_ids if alerts_count >= SecurityCampaigns::MAX_ALERTS_COUNT || repository_ids.size >= SecurityCampaigns.max_alerts_repository_count(this_organization)

          alerts_count += alert_count_by_repo_id[repo_id]
          repository_ids << repo_id
        end
      end
      repository_ids
    end
  end
end
