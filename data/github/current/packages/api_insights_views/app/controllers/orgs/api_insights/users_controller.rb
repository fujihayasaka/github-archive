# typed: strict
# frozen_string_literal: true

module Orgs
  module ApiInsights
    class UsersController < BaseController

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

      before_action :user_has_organization_activity
      after_action :instrument_index, only: [:index]

      TABLE_OPTIONS = T.let({
        type: {
          name: "Type",
          query_param: :type,
          mapping: {
            all: "All",
            oauth_app: "OAuth app",
            classic_pat: "Personal access token (classic)",
            fine_grained_pat: "Fine-grained personal access token",
            github_app_user_to_server: "GitHub App",
          },
          default: "all"
        },
        requests: {
          name: "Requests",
          query_param: :requests,
          mapping: {
            all: "All",
            rate: "Rate-limited requests",
          },
          default: "all"
        },
      }, T::Hash[Symbol, T::Hash[Symbol, T.untyped]])

      sig { void }
      def index
        page_params = default_page_params

        requestor_has_activity, summary_results, time_results, table_results = futures.map(&:value)

        errors = instrument_errors(futures)

        min, max = min_time_and_max_time

        render_react_app(
          title: "REST API insights",
          payload: {
            sidenav: sidenav,
            feedback_link: feedback_link,
            page_params: page_params,
            breadcrumb: user_breadcrumb(requestor_has_activity: requestor_has_activity),
            user_stats: user_stats(stat_result: summary_results),
            time_stats: time_stats(stat_result: time_results, min: min, max: max),
            time_filters: time_filters,
            requests_table: requests_table(stat_result: table_results, requestor_has_activity: requestor_has_activity),
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
          async_requestor_has_activity(organization_id: organization_id, user_id: user_id, force_synchronous: !use_async_kusto_calls?),
          async_user_summary_stats(min: min, max: max, organization_id: organization_id, user_id: user_id, force_synchronous: !use_async_kusto_calls?),
          async_user_time_stats(min: min, max: max, organization_id: organization_id, user_id: user_id, timestamp_increment: selected_bucket, force_synchronous: !use_async_kusto_calls?),
          async_user_stats(
            min: min,
            max: max,
            organization_id: organization_id,
            user_id: user_id,
            sorts: sort_definition_list,
            page: selected_page,
            per_page: PER_PAGE,
            name_prefix: selected_query,
            rate_limited_summaries: requests_filter && requests_filter[:group][:query_param] == :requests && requests_filter[:group][:selected_value] == "rate",
            type: has_type_filter ? ::ApiInsights::Stats::ActorType.from_serialized(type_filter[:group][:selected_value]) : nil,
            force_synchronous: !use_async_kusto_calls?
          ),
        ]
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      memoize def table_filters
        TABLE_OPTIONS.keys.map do |key|
          name, query_param, mapping, default = T.must(TABLE_OPTIONS[key]).values_at(:name, :query_param, :mapping, :default)
          selected_value = params[query_param] || default
          selected_value = default unless selected_value.to_sym.in?(mapping.keys)
          {
            name: name,
            group: {
              options: mapping.keys.map do |value|
                label = mapping[value]
                { name: label, value: value }
              end,
              selected_value: selected_value,
              query_param: query_param
            }
          }
        end
      end

      sig { params(requestor_has_activity: T.nilable(T::Hash[String, T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
      def user_breadcrumb(requestor_has_activity:)
        result = requestor_has_activity || { "subject_name" => nil, "subject_id" => nil }
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
          username: this_user&.safe_profile_name || result["subject_name"],
        }
      end

      sig do
        params(
          stat_result: T.nilable(::ApiInsights::Stats::StatsResult),
          requestor_has_activity: T.nilable(T::Hash[String, T.untyped])
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def requests_table(stat_result:, requestor_has_activity:)
        results = stat_result ? stat_result.records : []
        total_record_count = stat_result&.total_record_count || 0
        subject = requestor_has_activity || { "subject_name" => nil, "subject_id" => nil }

        integration_ids = []
        oauth_app_ids = []

        results.each do |r|
          if r["actor_type"] == "github_app_user_to_server" && r["integration_id"]
            integration_ids << r["integration_id"]
          elsif r["actor_type"] == "oauth_app"
            oauth_app_ids << r["oauth_application_id"]
          end
        end

        integrations = []
        if integration_ids.any?
          integrations = Integration.where(id: integration_ids).to_a
        end

        oauth_apps = []
        if oauth_app_ids.any?
          oauth_apps = OauthApplication.where(id: oauth_app_ids).to_a
        end

        rows = []

        results.each_with_index do |item, index|
          last_rate_limited = item["last_rate_limited_timestamp"]
          last_used = item["last_request_timestamp"]

          is_installation = item["actor_type"] == "github_app_user_to_server"
          is_oauth_app = item["actor_type"] == "oauth_app"
          is_classic_pat = item["actor_type"] == "classic_pat"

          icon_background_color = nil
          icon_url = nil
          name = nil

          if is_installation
            integration = integrations.find { |i| i.id == item["integration_id"] }
            name = item["actor_name"]
            if integration
              listing = integration.marketplace_listing
              icon_background_color = listing&.bgcolor
              icon_url = listing&.primary_avatar_url || integration.primary_avatar_url
            end
          elsif is_oauth_app
            name = item["actor_name"]
            oauth_app = oauth_apps.find { |i| i.id == item["oauth_application_id"] }
            icon_url = oauth_app&.primary_avatar_url
          elsif is_classic_pat
            name = this_user&.safe_profile_name || subject["subject_name"]
            icon_url = this_user&.primary_avatar_url
          else
            name = item["actor_name"]
            icon_url = this_user&.primary_avatar_url
          end
          rows << {
            id: index,
            name: name,
            total_requests: round_to_human(item["total_request_count"]),
            rate_limited_requests: round_to_human(item["rate_limited_request_count"]),
            last_rate_limited: last_rate_limited ? format_time_long(time: Time.iso8601(last_rate_limited).utc, user: current_user, local_time: local_time?) : "",
            description: T.must(TABLE_OPTIONS[:type])[:mapping][item["actor_type"].to_sym],
            href: actors_api_org_insights_path(
              org: this_organization,
              user: params[:user],
              actor_type: item["actor_type"],
              actor_id: item["actor_id"],
              period: params[:period],
              interval: params[:interval],
              **(params[:from] ? { from: params[:from] } : {}),
              **(params[:to] ? { to: params[:to] } : {}),
              t: params[:t],
              only_path: true
            ),
            installation_icon: is_installation,
            icon_url: icon_url,
            **(icon_background_color ? { icon_background_color: icon_background_color } : {}),
            **(is_oauth_app ? { square_icon: true } : {}),
          }
        end
        {
          title: "Actors",
          description: "View usage by app or user",
          placeholder_text: "Search for an app or user",
          pagination_text: "Pagination for actors",
          filters: table_filters,
          rows: rows,
          page_size: PER_PAGE,
          total_count: total_record_count,
        }
      end

      sig { params(stat_result: T.nilable(::ApiInsights::Stats::StatsResult)).returns(T::Hash[String, T.untyped]) }
      def user_stats(stat_result:)
        results = stat_result ? stat_result.records : []
        result = results.first || { "total_request_count" => 0, "rate_limited_request_count" => 0 }
        stats = {
          request_count: result["total_request_count"],
          rate_limited_request_count: result["rate_limited_request_count"],
          current_limit: GitHub.api_default_rate_limit
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

      sig { returns(Integer) }
      memoize def user_id
        params[:user].to_i
      end

      sig { returns(T.nilable(User)) }
      memoize def this_user
        User.find_by(id: user_id)
      end

      sig { void }
      def user_has_organization_activity
        requestor_has_activity = futures.first&.value
        return render_404 unless requestor_has_activity
        render_404 unless requestor_has_activity["subject_id"] && requestor_has_activity["subject_name"] && requestor_has_activity["subject_id"] == user_id
      end
    end
  end
end
