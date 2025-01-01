# typed: strict
# frozen_string_literal: true

module Orgs
  module ApiInsights
    class BaseController < Orgs::Controller
      extend T::Sig
      include ReactHelper
      include ApplicationController::VerifiedFetchDependency
      include ActionView::Helpers::NumberHelper

      before_action :api_insights_enabled_required

      sig { returns(String) }
      def self.react_bundle_name
        "api-insights"
      end

      VALUE_IN_SECONDS = T.let({
        m: 60,
        h: 3600,
        d: 86400,
      }.freeze, T::Hash[Symbol, Integer])

      protected

      LOOK_BACKS = T.let(%w[30m 1h 3h 12h 24h 7d 28d].freeze, T::Array[String])
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
            apps: "Apps",
            users: "Users",
          },
          default: "all"
        },
        requests: {
          name: "Requests",
          query_param: :requests,
          mapping: {
            all: "All",
            rate: "Rate limited requests",
          },
          default: "all"
        },
      }, T::Hash[Symbol, T::Hash[Symbol, T.untyped]])


      sig { params(time: Time).returns(String) }
      def format_time_long(time)
        if selected_time_zone == "local"
          return time.in_time_zone(current_user&.time_zone || Time.zone).strftime("%B %d, %Y %-I:%M%p %Z")
        end
        time.utc.strftime("%B %d, %Y %-I:%M%p %Z")
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

      sig { params(has_table_filters: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
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
        page_params.merge(
          {
            # table query
            **(params[:q] ? { q: params[:q]  } : {}),
            # table page
            p: [(params[:p].to_i || 1), 1].max,
            # custom range start
            **(params[:start] ? { start: params[:start] } : {}),
            # custom range end
            **(params[:end] ? { end: params[:end] } : {}),
            # name sort
            n: selected_sort(query_param: :n),
            # total requests sort
            tr: selected_sort(query_param: :tr),
            # rate limited requests sort
            rlr: selected_sort(query_param: :rlr),
            # last rate limited sort
            lrl: selected_sort(query_param: :lrl),
          }
        )
      end

      sig { returns(String) }
      def selected_time_zone
        time_zone = params[:t]
        return time_zone if time_zone.in?(TIME_ZONES)
        "UTC"
      end

      sig { params(query_param: Symbol).returns(T.nilable(String)) }
      def selected_sort(query_param:)
        sort = params[query_param]
        return sort if sort.in?(SORT_VALUES)
        SORT_VALUES.last
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      memoize def time_filters
        [
          {
            name: "Period",
            groups: [
              {
                name: "Period",
                options: time_options_for(entries: LOOK_BACKS, label_prefix: "Last").push({ name: "Custom", value: "custom", is_custom: true }),
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
        if selected_look_back == "custom"
          # TODO: get the start and end time from the query params
          return human_readable_duration_to_seconds("24h")
        end
        human_readable_duration_to_seconds(selected_look_back)
      end

      sig { returns(Integer) }
      memoize def selected_bucket_seconds
        human_readable_duration_to_seconds(selected_bucket)
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def sidenav
        {
          selectedKey: "api",
          showDependencies: this_organization&.dependency_insights_enabled_for?(current_user),
          showActionsUsageMetrics: this_organization&.actions_usage_metrics_enabled?(current_user),
          showActionsPerformanceMetrics: this_organization&.actions_performance_metrics_enabled?(current_user),
          showApi: true,
          urls: {
            dependency_insights: packages_dashboard_org_insights_path(this_organization),
            actions_usage_metrics: actions_usage_metrics_path(this_organization),
            actions_performance_metrics: actions_performance_metrics_path(this_organization),
            api: api_org_insights_path(this_organization)
          }
        }
      end

      sig { params(count: Integer).returns(String) }
      def round_to_human(count)
        units = { thousand: "k", million: "m", billion: "b" }
        number_to_human(count, precision: 1, significant: false, units: units, format: "%n%u")
      end

      sig { params(human_readable_duration: String).returns(Integer) }
      def human_readable_duration_to_seconds(human_readable_duration)
        base = human_readable_duration.to_i
        value_in_seconds = VALUE_IN_SECONDS[human_readable_duration.last.to_sym]
        value_in_seconds && base ? base * value_in_seconds : 86400
      end

      sig { void }
      def api_insights_enabled_required
        render_404 unless this_organization.api_insights_enabled?(current_user)
      end
    end
  end
end
