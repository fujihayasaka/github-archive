# typed: strict
# frozen_string_literal: true

# Shared logic for parsing @github-ui/filter-core date strings into Date /
# Date-Range values.  Both the rule-insights list (Repos::RulesHelper) and the
# rule-insights dashboard (InsightsDashboard::DashboardRoutePayload) include
# this module.
module Repos
  module Rules
    module CreatedDateFilter
      include DateMacroHelper
      extend self

      ISO_DATE_PATTERN = /\A(\d{4}-\d{2}-\d{2})\z/
      ISO_DATE_RANGE_PATTERN = /\A(\d{4}-\d{2}-\d{2})\.\.(\d{4}-\d{2}-\d{2})\z/
      GT_DATE_PATTERN = /\A>(=?)(\d{4}-\d{2}-\d{2})\z/
      LT_DATE_PATTERN = /\A<(=?)(\d{4}-\d{2}-\d{2})\z/

      # Parse a created-date filter value into a Date or Date Range.
      #
      # Returns +nil+ when the string is unrecognized or contains an unparsable
      # date, leaving callers free to choose their own fallback behaviour.
      #
      # +gt_lt_cap_days+: when set, caps open-ended > / < ranges to this many
      # days (e.g. 7 for the dashboard).  Pass +nil+ to leave ranges unbounded.
      sig do
        params(
          value: String,
          timezone: T.nilable(ActiveSupport::TimeZone),
          gt_lt_cap_days: T.nilable(Integer),
        ).returns(T.nilable(T.any(Date, T::Range[Date])))
      end
      def parse_created_date_value(value, timezone: ActiveSupport::TimeZone["UTC"], gt_lt_cap_days: nil)
        resolved = replace_today_macro(value, timezone: timezone, default_time_unit: DateMacroHelper::TimeUnit::Day)

        created = T.let(nil, T.nilable(T.any(Date, T::Range[Date])))
        begin
          case resolved
          when ISO_DATE_RANGE_PATTERN
            created = Date.parse($1)..Date.parse($2)
          when GT_DATE_PATTERN
            date = Date.parse($2)
            date += 1 if $1.empty?
            if gt_lt_cap_days
              created = date..(date + gt_lt_cap_days)
            else
              created = date..
            end
          when LT_DATE_PATTERN
            date = Date.parse($2)
            date -= 1 if $1.empty?
            if gt_lt_cap_days
              created = (date - gt_lt_cap_days)..date
            else
              created = ..date
            end
          when ISO_DATE_PATTERN
            created = Date.parse($1)
          end
          # Unrecognized patterns leave created as nil
        rescue Date::Error
          # Invalid date – leave created as nil
        end

        created
      end

      # Clamp a created filter (Date or Date Range) so it stays within the
      # window +[max_lookback, current_date]+.  Ranges that fall entirely
      # outside the window are collapsed to +max_lookback..max_lookback+ (or
      # +current_date..current_date+) so callers never receive an inverted
      # range.  The original range style (+..+ vs +...+) is preserved.
      sig do
        params(
          created: T.nilable(T.any(Date, T::Range[T.nilable(Date)])),
          max_lookback: Date,
          current_date: Date,
        ).returns(T.nilable(T.any(Date, T::Range[Date])))
      end
      def clamp_created_filter(created, max_lookback, current_date: Date.current)
        return created if created.nil?

        if created.is_a?(Range)
          range_begin = T.unsafe(created).begin
          range_end_val = T.unsafe(created).end
          clamped_begin = range_begin.is_a?(Date) ? [[range_begin, max_lookback].max, current_date].min : max_lookback
          clamped_end = range_end_val.is_a?(Date) ? [[range_end_val, max_lookback].max, current_date].min : current_date
          # Guarantee begin <= end after clamping
          clamped_end = [clamped_end, clamped_begin].max
          # When the range collapses to a single date, force inclusive so the
          # result isn't an empty exclusive range (date...date).
          exclude = clamped_begin == clamped_end ? false : T.unsafe(created).exclude_end?
          Range.new(clamped_begin, clamped_end, exclude)
        else
          clamped = [created, max_lookback].max
          clamped = [clamped, current_date].min
          clamped
        end
      end

      # Resolve a created-date filter string into a Time Range for dashboard use.
      # Always returns a valid range, defaulting to the last 7 days when the input
      # is empty or unparseable. The range spans from beginning_of_day to
      # end_of_day so callers can use it directly.
      sig do
        params(
          created: String,
          timezone: T.nilable(ActiveSupport::TimeZone),
          max_lookback_days: Integer,
        ).returns(T::Range[Time])
      end
      def resolve_dashboard_date_range(created, timezone:, max_lookback_days: 30)
        current_date = timezone ? Time.current.in_time_zone(timezone).to_date : Date.current
        max_lookback = current_date - max_lookback_days
        default_range = (current_date - 7)..current_date

        parsed = parse_created_date_value(created, timezone: timezone, gt_lt_cap_days: max_lookback_days)
        clamped = if parsed
          clamp_created_filter(parsed, max_lookback, current_date: current_date)
        end

        date_range = clamped || default_range
        date_range = date_range..date_range if date_range.is_a?(Date)

        date_range.begin.beginning_of_day..date_range.end.end_of_day
      end
    end
  end
end
