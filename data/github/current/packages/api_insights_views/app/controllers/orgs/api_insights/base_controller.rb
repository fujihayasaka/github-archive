# typed: strict
# frozen_string_literal: true

module Orgs
  module ApiInsights
    class BaseController < Orgs::Controller
      include ApplicationController::VerifiedFetchDependency

      include ::ApiInsights::Stats::AsyncDependency
      include Orgs::ApiInsights::FormatDependency

      before_action :api_insights_enabled_required

      sig { returns(String) }
      def self.react_bundle_name
        "api-insights"
      end

      protected

      PER_PAGE = 10
      LOOK_BACKS = T.let(%w[30m 1h 3h 12h 24h 7d 31d].freeze, T::Array[String])
      BUCKETS = T.let(%w[5m 10m 30m 1h 3h 12h 24h].freeze, T::Array[String])
      SORT_VALUES = T.let(%w[asc desc].freeze, T::Array[String])
      TIME_ZONES = T.let(%w[UTC local].freeze, T::Array[String])

      LABELS = T.let({
        m: "minute",
        h: "hour",
        d: "day",
      }.freeze, T::Hash[Symbol, String])

      TABLE_OPTIONS = T.let({
        type: {
          name: "Type",
          query_param: :type,
          mapping: {
            all: "All",
            installation: "Apps",
            user: "Users",
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

      GITHUB_PUBLIC_FEEDBACK_DISCUSSION = "https://github.co/api-insights-discussion"

      PRELOAD_FEATURE_FLAGS = T.let([
        :api_insights,
        :actions_usage_metrics,
        :api_insights_rest,
        :api_insights_use_secondary_tabular_input,
        :owner_scoped_github_apps,
        :remove_shelf_limited_paths,
        :reserved_domain,
        :copilot_conversational_ux_license_check,
        :copilot_natural_language_github_search,
        :azure_exp_staffbar,
        :command_palette_commands,
        :permission_enforcer_with_caching,
        :actions_usage_metrics_owner_bypass,
        :authnd_experiment,
        :slash_commands,
        :staff_cookie_default_to_canary,
        :copilot_custom_models_ga,
        :copilot_metrics_insights_navigator,
        :copilot_metrics_onboarding_timeline_page,
        :copilot_metrics_ui_for_all_members,
        :copilot_enabled_unconfigured,
        :copilot_metered_enterprise,
        :copilot_cb_rollout,
        :copilot_ce_rollout,
        :copilot_cs_rollout,
        :copilot_limited_rollout,
        :copilot_pro_plus_rollout,
        :copilot_pro_rollout,
        :enterprise_teams_migrate_from_cfb,
        :unaffiliated_user_accounts,
        :free_health_assessment_nudge,
        :saml_satisfied_debug_logging,
        :enterprise_teams_crud,
        :erp_preview_enterprise_teams_crud,
        :erp_staffship_enterprise_teams_crud,
        :enterprise_teams_org_authorization,
        :enterprise_teams_org_assignment,
        :erp_preview_enterprise_teams_org_assignment,
        :erp_staffship_enterprise_teams_org_assignment,
        :disable_notifications_automatic_watching_repositories,
        :disable_notifications_automatic_watching_teams,
        :limit_execution_time_notification_entries,
        :notifications_remove_force_index,
        :limit_execution_time_indicator,
        :hawaii_exp,
        :oauth_access_read_replica,
        :secret_scanning_first_scan_nudge_0,
        :secret_scanning_first_scan_nudge_1,
        :users_by_id_cache_interface,
        :use_replica_for_user_lookup_2558,
        :copilot_api_override_url_fallback,
      ].freeze, T::Array[Symbol])

      sig { returns(Integer) }
      def organization_id
        this_organization.id
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def sidenav
        {
          selectedKey: "api",
          showDependencies: this_organization&.dependency_insights_visible?(current_user),
          showActionsUsageMetrics: this_organization&.actions_usage_metrics_enabled?(current_user),
          showCopilotMetricsViewer: this_organization&.copilot_metrics_viewer_enabled?(current_user),
          showCopilotMetricsCatalog: this_organization&.copilot_metrics_catalog_enabled?(current_user),
          showApi: true,
          urls: {
            dependency_insights: packages_dashboard_org_insights_path(this_organization),
            actions_usage_metrics: actions_usage_metrics_path(this_organization),
            actions_performance_metrics: actions_performance_metrics_path(this_organization),
            api: api_org_insights_path(this_organization),
            copilot_metrics_insights: copilot_metrics_insights_path
          }
        }
      end

      sig { returns(String) }
      def copilot_metrics_insights_path
        if this_organization&.feature_flag_enabled?(:copilot_metrics_insights_navigator, default: false) || this_organization&.business&.feature_flag_enabled?(:copilot_metrics_insights_navigator, default: false)
          copilot_metrics_insights_catalog_org_insights_path(this_organization)
        else
          copilot_user_onboarding_org_insights_path(this_organization)
        end
      end

      sig { returns String }
      def feedback_link
        GITHUB_PUBLIC_FEEDBACK_DISCUSSION
      end

      sig { params(entries: T::Array[String], check_disabled: T::Boolean, upper_bound: Integer, label_prefix: T.nilable(String)).returns(T::Array[T::Hash[String, T.untyped]]) }
      def time_options_for(entries:, check_disabled: false, upper_bound: 0, label_prefix: nil)
        entries.map do |entry|
          unit = entry.last.to_sym
          value = entry.to_i
          {
            name: label_prefix ? "#{label_prefix} #{pluralize(value, LABELS[unit])}" : pluralize(value, LABELS[unit]),
            value: entry,
            **(check_disabled ? { disabled: upper_bound <= human_readable_duration_to_seconds(entry) } : {}),
          }
        end
      end

      sig { params(has_table_filters: T::Boolean).returns(T::Hash[Symbol, String]) }
      def default_page_params(has_table_filters: true)
        page_params = {}

        period, increment = time_filters
        T.must(period)[:groups].each do |group|
          page_params[group[:query_param]] = group[:selected_value]
        end
        increment_group = T.must(increment)[:group]
        page_params[increment_group[:query_param]] = increment_group[:selected_value]
        if has_table_filters
          table_filters.each do |item|
            group = item[:group]
            page_params[group[:query_param]] = group[:selected_value]
          end
        end

        from, to = selected_from_and_to

        page_params.merge(
          {
            # table query
            **(selected_query ? { q: selected_query } : {}),
            # table page
            p: selected_page,
            # custom range from
            **(custom_time_range? && from ? { from: from.iso8601(3) } : {}),
            # custom range to
            **(custom_time_range? && to ? { to: to.iso8601(3) } : {}),
            # http method sort
            **(selected_http_method_sort ? { m: selected_http_method_sort } : {}),
            # name sort
            **(selected_name_sort ? { n: selected_name_sort } : {}),
            # total requests sort
            **(selected_total_requests_sort ? { tr: selected_total_requests_sort } : {}),
            # rate limited requests sort
            **(selected_rate_limited_requests_sort ? { rlr: selected_rate_limited_requests_sort } : {}),
            # last rate limited sort
            **(selected_last_rate_limited_sort ? { lrl: selected_last_rate_limited_sort } : {}),
          }
        )
      end

      sig { returns T.nilable(String) }
      memoize def selected_query
        params[:q]
      end

      sig { returns Integer }
      memoize def selected_page
        [(params[:p].to_i || 1), 1].max
      end

      sig { returns T.nilable(String) }
      memoize def selected_http_method_sort
        return if params[:m].blank?
        selected_sort(query_param: :m)
      end

      sig { returns T.nilable(String) }
      memoize def selected_name_sort
        return if params[:n].blank?
        selected_sort(query_param: :n)
      end

      sig { returns T.nilable(String) }
      memoize def selected_total_requests_sort
        return SORT_VALUES.last if params[:n].blank? && params[:tr].blank? && params[:rlr].blank? && params[:lrl].blank? && params[:m].blank?
        return if params[:tr].blank?
        selected_sort(query_param: :tr)
      end
      sig { returns T.nilable(String) }
      memoize def selected_rate_limited_requests_sort
        return if params[:rlr].blank?
        selected_sort(query_param: :rlr)
      end

      sig { returns T.nilable(String) }
      memoize def selected_last_rate_limited_sort
        return if params[:lrl].blank?
        selected_sort(query_param: :lrl)
      end

      sig { returns([Time, Time]) }
      memoize def min_time_and_max_time
        if custom_time_range?
          from, to = selected_from_and_to
          return [from.to_time, to.to_time]
        end
        now = Time.now
        [now - selected_look_back_seconds, now]
      end

      sig { returns([Time, Time]) }
      memoize def selected_from_and_to
        from = params[:from] || ""
        to = params[:to] || ""
        now = Time.zone.now
        fallback = [(now - 1.hour).utc, now.utc]

        # Can parse dates?
        begin
          from_date = Time.iso8601(from).utc
          to_date = Time.iso8601(to).utc
        rescue ArgumentError => e
          return fallback
        end

        # Clamp to relevant range
        from_date = from_date.clamp(now - max_look_back_seconds, now)
        to_date = to_date.clamp(now - max_look_back_seconds, now)

        # Don't allow a range that is smaller than the smallest look back
        if (to_date - from_date).abs.to_i < human_readable_duration_to_seconds(LOOK_BACKS.first || "30m")
          return fallback
        end

        # Are dates in the right order?
        if from_date > to_date
          return [to_date, from_date]
        end
        [from_date, to_date]
      end

      sig { returns(String) }
      def selected_time_zone
        time_zone = params[:t]
        return time_zone if time_zone.in?(TIME_ZONES)
        "UTC"
      end

      sig { params(query_param: Symbol).returns(String) }
      def selected_sort(query_param:)
        sort = params[query_param]
        return sort if sort.in?(SORT_VALUES)
        SORT_VALUES.last || "desc"
      end

      sig { returns(T::Boolean) }
      memoize def local_time?
        selected_time_zone == "local"
      end

      sig { returns(T::Boolean) }
      memoize def custom_time_range?
        selected_look_back == "custom"
      end

      sig { returns(String) }
      memoize def get_custom_range_label
        if custom_time_range?
          from, to = selected_from_and_to
          from_label = format_time_short(time: from.to_time, user: current_user, local_time: local_time?)
          to_label = format_time_short(time: to.to_time, user: current_user, local_time: local_time?, with_time_zone: true)
          return "#{from_label} - #{to_label}"
        end
        "Custom"
      end

      sig { returns Integer }
      memoize def max_look_back_seconds
        human_readable_duration_to_seconds(LOOK_BACKS.last || "31d")
      end

      sig { params(is_route: T::Boolean).returns T::Array[::ApiInsights::Stats::Queries::SortDefinition] }
      def sort_definition_list(is_route: false)
        [
          *(::ApiInsights::Stats::Queries::SortDefinition.new(
            ::ApiInsights::Stats::Queries::SortField::HttpMethod,
            descending: selected_http_method_sort == "desc"
          ) if selected_http_method_sort && is_route),
          *(::ApiInsights::Stats::Queries::SortDefinition.new(
            ::ApiInsights::Stats::Queries::SortField::SubjectName,
            descending: selected_name_sort == "desc"
          ) if selected_name_sort && !is_route),
          *(::ApiInsights::Stats::Queries::SortDefinition.new(
            ::ApiInsights::Stats::Queries::SortField::ApiRoute,
            descending: selected_name_sort == "desc"
          ) if selected_name_sort && is_route),
          *(::ApiInsights::Stats::Queries::SortDefinition.new(
            ::ApiInsights::Stats::Queries::SortField::TotalRequestCount,
            descending: selected_total_requests_sort == "desc"
          ) if selected_total_requests_sort),
          *(::ApiInsights::Stats::Queries::SortDefinition.new(
            ::ApiInsights::Stats::Queries::SortField::RateLimitedRequestCount,
            descending: selected_rate_limited_requests_sort == "desc"
          ) if selected_rate_limited_requests_sort),
          *(::ApiInsights::Stats::Queries::SortDefinition.new(
            ::ApiInsights::Stats::Queries::SortField::LastRateLimitedTimestamp,
            descending: selected_last_rate_limited_sort == "desc"
          ) if selected_last_rate_limited_sort),
        ]
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      memoize def time_filters
        [
          {
            name: "Period",
            groups: [
              {
                name: "Period",
                options: time_options_for(entries: LOOK_BACKS, label_prefix: "Last").push({ name: get_custom_range_label, value: "custom", is_custom: true }),
                selected_value: selected_look_back,
                query_param: :period,
              },
              {
                name: "Time zone",
                options: TIME_ZONES.map do |key|
                  { name: key.first.upcase != key.first ? key.capitalize : key, value: key }
                end,
                selected_value: selected_time_zone,
                query_param: :t,
              }
            ],
            period_in_seconds: selected_look_back_seconds,
            max_range_in_seconds: max_look_back_seconds,
            time_zone: get_time_zone_string(user: current_user, local_time: local_time?),
          },
          {
            name: "Interval",
            group: {
              options: time_options_for(entries: BUCKETS, check_disabled: true, upper_bound: selected_look_back_seconds),
              selected_value: selected_bucket,
              query_param: :interval
            }
          }
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

      sig { returns(String) }
      memoize def selected_look_back
        period = params[:period] || "24h"
        return period if period.in?(LOOK_BACKS) || period == "custom"
        "24h"
      end

      sig { returns(String) }
      memoize def selected_bucket
        selected = params[:interval]
        selected = "1h" unless selected.in?(BUCKETS)
        if human_readable_duration_to_seconds(selected) >= selected_look_back_seconds
          selected = BUCKETS.reverse_each do |bucket|
            break bucket if human_readable_duration_to_seconds(bucket) < selected_look_back_seconds
          end
        end
        selected
      end

      sig { returns(Integer) }
      memoize def selected_look_back_seconds
        if custom_time_range?
          from, to = selected_from_and_to
          return (to - from).to_i
        end
        human_readable_duration_to_seconds(selected_look_back)
      end

      sig { returns(Integer) }
      memoize def selected_bucket_seconds
        human_readable_duration_to_seconds(selected_bucket)
      end

      sig { params(futures: T::Array[Concurrent::Promises::Future]).returns(T::Array[String]) }
      def instrument_errors(futures)
        errors = futures.map(&:reason).compact.map do |error|
          Failbot.report(error)
          if error.is_a?(::ApiInsights::Stats::Error)
            error.code.to_error_message
          else
            "Failed to load API insights data"
          end
        end
        GitHub.dogstats.increment("api_insights_controllers.kusto_query", tags: ["success:#{errors.length == 0}"])
        errors
      end

      sig { void }
      def instrument_index
        label_params = ""
        default_page_params.each do |key, value|
          label_params += "#{key}:#{value};"
        end
        analytics_event(
          category: "api_insights",
          action: "api_insights_view",
          label: "organization_id:#{this_organization.id};#{label_params}"
        )
      end

      sig { void }
      def api_insights_enabled_required
        render_404 unless this_organization.api_insights_enabled?(current_user)
      end
    end
  end
end
