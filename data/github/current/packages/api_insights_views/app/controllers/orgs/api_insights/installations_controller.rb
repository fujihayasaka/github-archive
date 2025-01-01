# typed: strict
# frozen_string_literal: true

module Orgs
  module ApiInsights
    class InstallationsController < BaseController

      preload_features PRELOAD_FEATURE_FLAGS

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Billing,
        ApplicationRecord::Copilot,
        ApplicationRecord::Repositories,
        only: [:index]

      before_action :installation_has_organization_activity
      after_action :instrument_index, only: [:index]

      sig { void }
      def index
        min, max = min_time_and_max_time

        page_params = default_page_params(has_table_filters: false)

        requestor_has_activity, summary_results, time_results, route_results = futures.map(&:value)

        errors = instrument_errors(futures)

        render_react_app(
          title: "REST API insights",
          payload: {
            sidenav: sidenav,
            feedback_link: feedback_link,
            page_params: page_params,
            breadcrumb: installations_breadcrumb(requestor_has_activity: requestor_has_activity),
            installation_stats: installation_stats(stat_result: summary_results),
            time_stats: time_stats(stat_result: time_results, min: min, max: max),
            time_filters: time_filters,
            requests_table: requests_table(stat_result: route_results),
            **(errors.present? ? { error: errors.first } : {}),
          },
          page_data: { selected_link: :insights },
          ssr: false, # disabled until guidance is updated to allow SSR
        )
      end

      private

      sig { returns T::Array[Concurrent::Promises::Future] }
      memoize def futures
        min, max = min_time_and_max_time
        [
          async_requestor_has_activity(organization_id: organization_id, installation_id: installation_id, force_synchronous: !use_async_kusto_calls?),
          async_installation_summary_stats(min: min, max: max, organization_id: organization_id, installation_id: installation_id, force_synchronous: !use_async_kusto_calls?),
          async_installation_time_stats(min: min, max: max, organization_id: organization_id, timestamp_increment: selected_bucket, installation_id: installation_id, force_synchronous: !use_async_kusto_calls?),
          async_route_installation_stats(
            organization_id: organization_id,
            min: min,
            max: max,
            installation_id: installation_id,
            page: selected_page,
            per_page: PER_PAGE,
            sorts: sort_definition_list(is_route: true),
            route_prefix: selected_query,
            force_synchronous: !use_async_kusto_calls?
          )
        ]
      end

      sig { params(requestor_has_activity: T.nilable(T::Hash[String, T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
      def installations_breadcrumb(requestor_has_activity:)
        result = requestor_has_activity || { "actor_name" => nil, "actor_id" => nil }
        {
          api_insights_base_url: api_org_insights_path(
            this_organization,
            period: params[:period],
            interval: params[:interval],
            **(params[:from] ? { from: params[:from] } : {}),
            **(params[:to] ? { to: params[:to] } : {}),
            t: params[:t],
            only_path: true
          ),
          name: result["actor_name"] || "Installation",
        }
      end

      sig { params(stat_result: T.nilable(::ApiInsights::Stats::StatsResult)).returns(T::Hash[Symbol, T.untyped]) }
      def requests_table(stat_result:)
        results = stat_result ? stat_result.records : []
        total_record_count = stat_result&.total_record_count || 0

        rows = []
        results.each_with_index do |item, index|
          last_rate_limited = item["last_rate_limited_timestamp"]
          last_used = item["last_request_timestamp"]
          rows << {
            id: index,
            http_method: item["http_method"],
            name: item["api_route"],
            total_requests: round_to_human(item["total_request_count"]),
            rate_limited_requests: round_to_human(item["rate_limited_request_count"]),
            last_rate_limited: last_rate_limited ? format_time_long(time: Time.iso8601(last_rate_limited).utc, user: current_user, local_time: local_time?) : "",
            description: last_used ? "Last used #{format_time_long(time: Time.iso8601(last_used).utc, user: current_user, local_time: local_time?)}" : ""
          }
        end

        {
          title: "Routes",
          description: "View usage by individual API route",
          placeholder_text: "Search for a route",
          pagination_text: "Pagination for routes",
          variant: "routes",
          rows: rows,
          page_size: PER_PAGE,
          total_count: total_record_count,
        }
      end

      sig { params(stat_result: T.nilable(::ApiInsights::Stats::StatsResult)).returns(T::Hash[Symbol, T.untyped]) }
      def installation_stats(stat_result:)
        results = stat_result ? stat_result.records : []
        result = results.first || { "total_request_count" => 0, "rate_limited_request_count" => 0 }

        local_installation = this_integration_installation
        if local_installation
          limit = ::ApiInsights::Stats::RateLimit
            .new(::Api::RateLimitConfiguration::DEFAULT_FAMILY)
            .for_installation(local_installation)
        end

        stats = {
          request_count: round_to_human(result["total_request_count"]),
          rate_limited_request_count: round_to_human(result["rate_limited_request_count"]),
          current_limit: limit.nil? ? nil : round_to_human(limit)
        }
      end

      sig { params(stat_result: T.nilable(::ApiInsights::Stats::StatsResult), min: Time, max: Time).returns(T::Hash[Symbol, T.untyped]) }
      def time_stats(stat_result:, min:, max:)
        results = stat_result ? stat_result.records : []
        time_stats = { min: min.to_i * 1000, max: max.to_i * 1000, request_count: [], rate_limited_request_count: [], no_data: results.empty? }
        results.each do |point|
          timestamp = Time.iso8601(point["timestamp"]).utc.to_i * 1000
          time_stats[:request_count] << [timestamp, point["total_request_count"]]
          time_stats[:rate_limited_request_count] << [timestamp, point["rate_limited_request_count"]]
        end
        time_stats
      end

      sig { returns(T.nilable(IntegrationInstallation)) }
      memoize def this_integration_installation
        this_organization&.integration_installations&.where(id: installation_id)&.first
      end

      sig { returns(Integer) }
      memoize def installation_id
        params[:installation_id].to_i
      end

      sig { void }
      def installation_has_organization_activity
        return render_404 unless installation_id.to_s == params[:installation_id]
        requestor_has_activity = futures.first&.value
        return render_404 unless requestor_has_activity
        render_404 unless requestor_has_activity["actor_name"] && requestor_has_activity["actor_id"] && requestor_has_activity["actor_id"] == installation_id
      end
    end
  end
end
