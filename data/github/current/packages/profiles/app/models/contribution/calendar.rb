# typed: true
# frozen_string_literal: true

# The Contribution::Calendar deals with a user's contributions over time.
class Contribution::Calendar
  DEFAULT_ZERO_COLOR = "#ebedf0".freeze
  HALLOWEEN_COLORS = %w[#ffee4a #ffc501 #fe9600 #03001c].freeze
  WINTER_COLORS = %w[#B6E3FF #54AEFF #0969DA #0A3069].freeze
  DEFAULT_COLORS = %w[#9be9a8 #40c463 #30a14e #216e39].freeze
  CACHE_VERSION = 2

  SOUTHERN_HEMISPHERE_COUNTRY_CODES = %w(AO AR AU BI BO BR BW CD CG CL EC FJ GA KM LS MG MU MW MZ NA NR NZ PE PG PY RW SB SC SZ TL TV TZ UY VU WS ZA ZM ZW).freeze

  attr_reader :user, :viewer, :from, :to, :organization_id

  # Moment we switched to timezone aware contribution graphs
  TIMEZONE_AWARE_CUTOVER = Time.utc(2014, 3, 10)

  # Public: Return a time range that represents the span shown by a Calendar.
  #
  # to - Date or Time representing the end of the range.
  #
  # Returns a Range of Times.
  def self.time_range_ending_on(to)
    ends_on_last_day_of_year = to.end_of_year.to_date == to.to_date

    from = if ends_on_last_day_of_year
      to.beginning_of_year.beginning_of_week(:sunday)
    else
      (to - 1.year).beginning_of_week(:sunday)
    end

    from.beginning_of_day..to.end_of_day
  end

  # collector - The Contribution::Collector that is responsible for fetching data
  #             for this calendar. It should be scoped to a 1-year time range.
  def initialize(collector:)
    @user = collector.user
    @viewer = collector.viewer
    @time_range = collector.time_range
    @to = @time_range.end.to_date
    @from = @time_range.begin.to_date
    @organization_id = collector.organization_id
    @collector = collector
  end

  # Public: The login of the user this calendar represents.
  #
  # Returns a String.
  def user_login
    user.display_login
  end

  # Public: The count of total contributions in the calendar.
  # Returns an Integer.
  def total_contributions
    days.sum { |_day, count| count }
  end

  # Public: Determine if the current time (not the from-to range for this calendar) is Halloween.
  #
  # Returns a Boolean.
  def halloween?
    current_time = Time.zone.now
    start  = Time.zone.local(current_time.year, 10, 31) # 2014-10-31 00:00:00
    finish = Time.zone.local(current_time.year, 11, 1) # 2014-11-01 00:00:00

    current_time >= start && current_time < finish
  end

  # Public: Determine if the current time (not the from-to range for this calendar) is eligible for winter colors.
  #
  # Returns a Boolean.
  def winter_colors?
    return false unless GitHub.flipper[:contribution_graph_winter_theme].enabled?(viewer)

    first_day_of_winter_in_hemisphere?(:north) && viewer_in_hemisphere?(:north) ||
      first_day_of_winter_in_hemisphere?(:south) && viewer_in_hemisphere?(:south)
  end

  # Public: Determine if the current period is a holiday period such as 'halloween' or 'winter'.
  #
  # Returns a String or nil.
  def holiday_period
    return "winter" if winter_colors?
    return "halloween" if halloween?
    nil
  end

  # Public: Returns a Quantile for the days in this calendar using the range of colors that suit
  # the current time (Holiday period versus not).
  def quantile
    outliers = OutlierFilter.new
    counts = days.map { |pair| pair[1] }
    counts = outliers.filter(counts)
    Quantile.new(domain: [0, counts.max.to_i], range: colors)
  end

  # Public: Collection of daily contributions for a specific user based on the
  # viewer. Includes entries for all days even when they have 0 as a value.
  #
  # Returns an Array of [[day, count],...]
  def days
    @days ||= days!
  end

  def platform_type_name
    "ContributionCalendar"
  end

  def self.weeks_from(days, quantile:)
    calendar_days = days.map do |date, count|
      color = count.zero? ? DEFAULT_ZERO_COLOR : quantile.scale(count)
      level = count.zero? ? 0 : quantile.n_quantile(count) + 1
      ::Contribution::CalendarDay.new(date: date, count: count, color: color, level: level)
    end
    lists_of_squares = calendar_days.slice_before(&:sunday?).to_a

    max_weeks = 53 # SVG only has room for 53 columns representing a week each
    if lists_of_squares.size > max_weeks
      # Keep the most recent weeks
      lists_of_squares = lists_of_squares.drop(lists_of_squares.size - max_weeks)
    end

    lists_of_squares.map do |contrib_squares|
      ::Contribution::CalendarWeek.new(contrib_squares)
    end
  end

  def weeks
    self.class.weeks_from(days, quantile: quantile)
  end

  def self.months_from(weeks)
    weeks_by_month = weeks.group_by do |calendar_week|
      days = calendar_week.contribution_days
      earliest_day = days.first
      date = earliest_day.date
      date.beginning_of_month
    end

    weeks_by_month.map do |first_day, weeks|
      ::Contribution::CalendarMonth.new(first_day: first_day, total_weeks: weeks.size)
    end
  end

  def months
    self.class.months_from(weeks)
  end

  sig { params(weeks: T::Array[Contribution::CalendarWeek]).returns(T::Array[T::Array[Contribution::CalendarDay]]) }
  def self.days_of_week_from(weeks)
    result = Array.new(7) { [] }
    weeks.each do |week|
      # We always add one element to each array for each week, even if that element is `nil`
      result.each_with_index do |arr, i|
        arr.push(week.contribution_days.find { |day| day.weekday == i })
      end
    end
    result
  end

  # Public: Contribution days grouped by 'day of week' in order
  #
  # Returns an `Array` of seven `Array`s, one for each day of the week. Sub-arrays will always all have the same number of
  # elements; empty cells are filled with `nil`.
  sig { returns(T::Array[T::Array[Contribution::CalendarDay]]) }
  def days_of_week
    self.class.days_of_week_from(weeks)
  end

  def async_url
    path = "/users/{login}/contributions?to={to}"
    template_args = { login: user_login, to: to.iso8601 }

    if organization_id
      org_promise = Platform::Loaders::ActiveRecord.load(::Organization, organization_id)
      org_promise.then do |org|
        if org
          path += "&org={org}"
          template_args[:org] = org.display_login
        end
        Addressable::Template.new(path).expand(template_args)
      end
    else
      Addressable::Template.new(path).expand(template_args)
    end
  end

  # Public: Colors for each weighted contribution on the contribution calendar.
  #
  # Returns an Array of String hex color codes.
  def colors
    @colors ||= begin
      if halloween?
        HALLOWEEN_COLORS
      elsif winter_colors?
        WINTER_COLORS
      else
        DEFAULT_COLORS
      end
    end
  end

  private

  # Private: Determine if the viewer is in the given hemisphere.
  #
  # Returns a Boolean.
  def viewer_in_hemisphere?(hemisphere)
    return false unless viewer&.time_zone_name.present?

    southern_hemisphere_timezones = SOUTHERN_HEMISPHERE_COUNTRY_CODES
      .flat_map { |country_code| Sponsors::TimeZone.names(country_code: country_code).to_a }

    viewer_in_southern_hemisphere = southern_hemisphere_timezones.include?(viewer.time_zone_name)
    hemisphere == :south ? viewer_in_southern_hemisphere : !viewer_in_southern_hemisphere
  end

  # Private: Determine if the current time is the first day
  # of winter in the viewer's hemisphere.
  #
  # Returns a Boolean.
  def first_day_of_winter_in_hemisphere?(hemisphere)
    current_time = Time.zone.now

    if hemisphere == :south
      start  = Time.zone.local(current_time.year, 06, 21) # 2022-06-21 00:00:00
      finish = Time.zone.local(current_time.year, 06, 22) # 2022-06-22 00:00:00
    else
      start  = Time.zone.local(current_time.year, 12, 21) # 2022-12-21 00:00:00
      finish = Time.zone.local(current_time.year, 12, 22) # 2022-12-22 00:00:00
    end

    current_time >= start && current_time < finish
  end

  # Private: Collection of daily contributions for a specific
  # user based on the viewer.
  #
  # Returns an Array of [[day, count],...]
  def days!
    data = {}
    contribution_days = @collector.contribution_count_by_day

    end_date = @to

    if contribution_days.present?
      latest_contribution_date = contribution_days.keys.max

      if (latest_contribution_date - end_date).to_i <= 1 # days between
        end_date = [latest_contribution_date, end_date].max
      end
    end

    @from.upto(end_date) do |day|
      data[day] = contribution_days[day] || 0
    end

    data.sort_by { |date, _contribs| date }
  end
end
