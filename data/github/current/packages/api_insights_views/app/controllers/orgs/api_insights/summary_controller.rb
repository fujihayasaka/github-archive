# typed: strict
# frozen_string_literal: true

module Orgs
  module ApiInsights
    class SummaryController < BaseController

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

      after_action :instrument_index, only: [:index]

      sig { void }
      def index
        page_params = default_page_params

        summary_results, time_results, table_results = futures.map(&:value)

        errors = instrument_errors(futures)

        min, max = min_time_and_max_time

        render_react_app(
          title: "REST API insights",
          payload: {
            sidenav: sidenav,
            feedback_link: feedback_link,
            page_params: page_params,
            summary_stats: summary_stats(stat_result: summary_results),
            time_stats: time_stats(stat_result: time_results, min: min, max: max),
            time_filters: time_filters,
            requests_table: requests_table(stat_result: table_results),
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

        type_filter, requests_filter = table_filters

        has_type_filter = type_filter && type_filter[:group][:query_param] == :type && type_filter[:group][:selected_value] != "all"

        [
          async_summary_stats(min: min, max: max, organization_id: organization_id, force_synchronous: !use_async_kusto_calls?),
          async_summary_time_stats(min: min, max: max, organization_id: organization_id, timestamp_increment: selected_bucket, force_synchronous: !use_async_kusto_calls?),
          async_summary_subject_stats(
            min: min,
            max: max,
            organization_id: organization_id,
            sorts: sort_definition_list,
            page: selected_page,
            per_page: PER_PAGE,
            rate_limited_summaries: requests_filter && requests_filter[:group][:query_param] == :requests && requests_filter[:group][:selected_value] == "rate",
            subject_type: has_type_filter ? ::ApiInsights::Stats::SubjectType.from_serialized(type_filter[:group][:selected_value]) : nil,
            name_prefix: selected_query,
            force_synchronous: !use_async_kusto_calls?
          ),
        ]
      end

      sig { params(stat_result: T.nilable(::ApiInsights::Stats::StatsResult)).returns(T::Hash[Symbol, T.untyped]) }
      def requests_table(stat_result:)
        results = stat_result ? stat_result.records : []
        total_record_count = stat_result&.total_record_count || 0

        integration_ids = []
        user_ids = []

        results.each do |r|
          if r["subject_type"] == "installation" && r["integration_id"]
            integration_ids << r["integration_id"]
          elsif r["subject_type"] == "user"
            user_ids << r["subject_id"]
          end
        end

        integrations = []
        if integration_ids.any?
          integrations = Integration.where(id: integration_ids).to_a
        end

        users = []
        if user_ids.any?
          users = User.where(id: [user_ids]).to_a
        end

        {
          title: "Actors",
          description: "View usage by app or user",
          placeholder_text: "Search for an app or user",
          pagination_text: "Pagination for actors",
          filters: table_filters,
          rows: requests_table_rows(results, integrations, users),
          page_size: PER_PAGE,
          total_count: total_record_count,
        }
      end

      sig do
        params(
          results: T::Array[T::Hash[String, T.untyped]],
          integrations: T::Array[Integration],
          users: T::Array[User]
        )
        .returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def requests_table_rows(results, integrations, users)
        rows = []
        results.each_with_index do |item, index|
          is_installation = item["subject_type"] == "installation"
          last_rate_limited = item["last_rate_limited_timestamp"]

          icon_url = nil
          icon_background_color = nil
          description = nil

          if is_installation
            description = "GitHub App"
            integration = integrations.find { |i| i.id == item["integration_id"] }
            href = installations_api_org_insights_path(
              org: this_organization,
              installation_id: item["subject_id"],
              period: params[:period],
              interval: params[:interval],
              **(params[:from] ? { from: params[:from] } : {}),
              **(params[:to] ? { to: params[:to] } : {}),
              t: params[:t],
              only_path: true
            )
            if integration
              listing = integration.marketplace_listing
              icon_background_color = listing&.bgcolor
              icon_url = listing&.primary_avatar_url || integration.primary_avatar_url
            end
            name = integration&.name || item["subject_name"]
          else
            user = users.find { |u| u.id == item["subject_id"] }
            name = user&.safe_profile_name || item["subject_name"]
            description = user&.display_login || item["subject_name"]
            href = users_api_org_insights_path(
              org: this_organization,
              user: item["subject_id"],
              period: params[:period],
              interval: params[:interval],
              **(params[:from] ? { from: params[:from] } : {}),
              **(params[:to] ? { to: params[:to] } : {}),
              t: params[:t],
              only_path: true
            )
            icon_url = user&.primary_avatar_url
          end
          rows << {
            id: index,
            name: name,
            total_requests: round_to_human(item["total_request_count"]),
            rate_limited_requests: round_to_human(item["rate_limited_request_count"]),
            last_rate_limited: last_rate_limited ? format_time_long(time: Time.iso8601(last_rate_limited).utc, user: current_user, local_time: local_time?) : "",
            description: description,
            href: href,
            installation_icon: is_installation,
            icon_url: icon_url,
            **(icon_background_color ? { icon_background_color: icon_background_color } : {}),
          }
        end
        rows
      end

      sig { params(stat_result: T.nilable(::ApiInsights::Stats::StatsResult)).returns(T::Hash[Symbol, T.untyped]) }
      def summary_stats(stat_result:)
        results = stat_result ? stat_result.records : []
        result = results.first || { "total_request_count" => 0, "rate_limited_request_count" => 0 }
        stats = {
          request_count: result["total_request_count"],
          rate_limited_request_count: result["rate_limited_request_count"]
        }
        stats.transform_values { |v| round_to_human(v) }
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
    end
  end
end
