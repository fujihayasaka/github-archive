# typed: strict
# frozen_string_literal: true

module Orgs
  module ApiInsights
    class ActorsController < BaseController

      class OauthAccessMissingIntegration < StandardError; end

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

      before_action :enforce_actor_types
      before_action :actor_has_organization_activity
      after_action :instrument_index, only: [:index]

      MAX_CONTRIBUTORS = 30

      sig { void }
      def index

        min, max = min_time_and_max_time

        page_params = default_page_params(has_table_filters: false)

        requestor_has_activity, summary_results, user_summary_results, time_results, route_results, contributor_results = futures.map(&:value)

        errors = instrument_errors(futures)

        render_react_app(
          title: "REST API insights",
          payload: {
            sidenav: sidenav,
            feedback_link: feedback_link,
            page_params: page_params,
            username: username(requestor_has_activity),
            breadcrumb: breadcrumb(requestor_has_activity),
            actor_stats: actor_stats(stat_result: summary_results, user_summary_results: user_summary_results),
            contributors: contributors(
              stat_result: contributor_results,
              user_summary_results: user_summary_results,
              requestor_has_activity: requestor_has_activity
            ),
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

      sig { params(type: String).returns(String) }
      def label(type)
        begin
          ::ApiInsights::Stats::ActorType.from_serialized(type)
        rescue KeyError => e
          return ""
        end
        case type
        when "oauth_app"
          "OAuth app"
        when "classic_pat"
          "Personal access token (classic)"
        when "fine_grained_pat"
          "Fine-grained personal access token"
        else
          "GitHub App"
        end
      end

      sig do
        params(
          requestor_has_activity: T.nilable(T::Hash[String, T.untyped]),
        ).returns(String)
      end
      def username(requestor_has_activity)
        this_user&.safe_profile_name || requestor_has_activity&.dig("subject_name") || "User"
      end

      sig do
        params(
          requestor_has_activity: T.nilable(T::Hash[String, T.untyped]),
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def breadcrumb(requestor_has_activity)
        result = requestor_has_activity || { "actor_name" => nil, "actor_id" => nil }
        is_classic_pat = params["actor_type"] == "classic_pat"
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
          api_insights_user_url: users_api_org_insights_path(
            org: this_organization,
            user: params[:user],
            period: params[:period],
            interval: params[:interval],
            **(params[:from] ? { from: params[:from] } : {}),
            **(params[:to] ? { to: params[:to] } : {}),
            t: params[:t],
            only_path: true
          ),
          actor_name: is_classic_pat ? username(requestor_has_activity) : result["actor_name"],
          label: label(params["actor_type"]),
        }
      end

      sig do
        params(
          stat_result: T.nilable(::ApiInsights::Stats::StatsResult),
          user_summary_results: T.nilable(::ApiInsights::Stats::StatsResult),
          requestor_has_activity: T.nilable(T::Hash[String, T.untyped])
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def contributors(stat_result:, user_summary_results:, requestor_has_activity:)
        results = stat_result ? stat_result.records : []
        total_record_count = stat_result&.total_record_count || 0

        user_summary_results = user_summary_results ? user_summary_results.records : []
        user_summary_result = user_summary_results.first || { "total_request_count" => 0, "rate_limited_request_count" => 0 }
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
            oauth_app = oauth_apps.find { |i| i.id == item["oauth_application_id"] }
            name = item["actor_name"]
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
            requests: round_to_human(item["total_request_count"]),
            actor_type: label(item["actor_type"]),
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
          request_contributors_table: { rows: rows },
          total_contributors_requests: round_to_human(user_summary_result["total_request_count"]),
          results: results,
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
            description: last_used ? "Last used #{format_time_long(time: Time.iso8601(last_used).utc, user: current_user, local_time: local_time?)}" : "",
          }
        end
        {
          title: "Routes",
          description: "View usage by API route",
          placeholder_text: "Search for a route",
          pagination_text: "Pagination for routes",
          variant: "routes",
          rows: rows,
          page_size: PER_PAGE,
          total_count: total_record_count,
        }
      end

      sig do
        params(
          stat_result: T.nilable(::ApiInsights::Stats::StatsResult),
          user_summary_results: T.nilable(::ApiInsights::Stats::StatsResult)
        )
        .returns(T::Hash[Symbol, T.untyped])
      end
      def actor_stats(stat_result:, user_summary_results:)
        results = stat_result ? stat_result.records : []
        result = results.first || { "total_request_count" => 0, "rate_limited_request_count" => 0 }

        user_summary_results = user_summary_results ? user_summary_results.records : []
        user_summary_result = user_summary_results.first || { "total_request_count" => 0, "rate_limited_request_count" => 0 }

        if result["total_request_count"] > 0 && user_summary_result["total_request_count"] > 0
          this_app = ((result["total_request_count"].to_f / user_summary_result["total_request_count"].to_f) * 1000.0).round / 10.0
          breakdown = [this_app, ((100.0 - this_app) * 10.0).round / 10.0]
        end

        core_rate_limit = ::ApiInsights::Stats::RateLimit.new(::Api::RateLimitConfiguration::DEFAULT_FAMILY)
        limit = case actor_type
        when ::ApiInsights::Stats::ActorType::OauthApp
          access = OauthAccess.find_by(id: actor_id)
          access.nil? ? nil : core_rate_limit.for_oauth_application(access)
        when ::ApiInsights::Stats::ActorType::GithubAppUserToServer
          access = OauthAccess.find_by(id: actor_id)
          integration = access&.integration
          if access && integration.nil?
            Failbot.report(OauthAccessMissingIntegration.new("Integration is nil for oauth access #{actor_id}"))
          end
          integration.nil? ? nil : core_rate_limit.for_integration(integration)
        when ::ApiInsights::Stats::ActorType::ClassicPat, ::ApiInsights::Stats::ActorType::FineGrainedPat
          GitHub.api_default_rate_limit
        end

        stats = {
          request_count: round_to_human(result["total_request_count"]),
          rate_limited_request_count: round_to_human(result["rate_limited_request_count"]),
          current_limit: limit.nil? ? nil : round_to_human(limit),
          **(breakdown ? { legend: ["This app", "Other apps"] } : {}),
          **(breakdown ? { breakdown: breakdown } : {}),
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

      sig { returns T::Array[Concurrent::Promises::Future] }
      memoize def futures
        min, max = min_time_and_max_time
        [
          async_requestor_has_activity(organization_id: organization_id, actor_id: actor_id, actor_type: actor_type, force_synchronous: !use_async_kusto_calls?),
          async_actor_summary_stats(min: min, max: max, organization_id: organization_id, actor_id: actor_id, actor_type: actor_type, force_synchronous: !use_async_kusto_calls?),
          async_user_summary_stats(min: min, max: max, organization_id: organization_id, user_id: user_id, force_synchronous: !use_async_kusto_calls?),
          async_actor_time_stats(min: min, max: max, organization_id: organization_id, actor_id: actor_id, actor_type: actor_type, timestamp_increment: selected_bucket, force_synchronous: !use_async_kusto_calls?),
          async_actor_route_installation_stats(
            min: min,
            max: max,
            organization_id: organization_id,
            actor_id: actor_id,
            actor_type: actor_type,
            page: selected_page,
            per_page: PER_PAGE,
            sorts: sort_definition_list(is_route: true),
            route_prefix: selected_query,
            force_synchronous: !use_async_kusto_calls?,
          ),
          async_user_stats(
            min: min,
            max: max,
            organization_id: organization_id,
            user_id: user_id,
            sorts: [::ApiInsights::Stats::Queries::SortDefinition.new(
              ::ApiInsights::Stats::Queries::SortField::TotalRequestCount,
              descending: true
            )],
            page: 1,
            per_page: MAX_CONTRIBUTORS,
            name_prefix: nil,
            rate_limited_summaries: false,
            type: nil,
            force_synchronous: !use_async_kusto_calls?,
          ),
        ]
      end

      sig { returns T.nilable(::ApiInsights::Stats::ActorType) }
      memoize def actor_type
        begin
          ::ApiInsights::Stats::ActorType.from_serialized(params[:actor_type])
        rescue KeyError => e
          nil
        end
      end

      sig { returns(Integer) }
      memoize def user_id
        params[:user].to_i
      end

      sig { returns(Integer) }
      memoize def actor_id
        params[:actor_id].to_i
      end

      sig { returns(T.nilable(User)) }
      memoize def this_user
        User.find_by(id: user_id)
      end

      sig { void }
      def enforce_actor_types
        render_404 unless actor_type
      end

      sig { void }
      def actor_has_organization_activity
        return render_404 unless actor_id.to_s == params[:actor_id]
        requestor_has_activity = futures.first&.value
        return render_404 unless requestor_has_activity
        return render_404 unless requestor_has_activity["subject_id"] && requestor_has_activity["subject_id"] == user_id
        render_404 unless requestor_has_activity["actor_name"] && requestor_has_activity["actor_id"] && requestor_has_activity["actor_id"] == actor_id
      end
    end
  end
end
