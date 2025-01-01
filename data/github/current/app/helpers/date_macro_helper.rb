# typed: strict
# frozen_string_literal: true

module DateMacroHelper
  extend T::Sig

  class TimeUnit < T::Enum
    enums do
      Day = new("d")
      Week = new("w")
      Month = new("m")
      Year = new("y")
    end
  end

  # Replaces references to the macro @today (along with optional arithmetic)
  # with an appropriate date in YYYY-MM-DD format.
  #
  # EXAMPLES:
  #
  #   "@today" ==> "2024-08-08"
  #   "@today+1d" ==> "2024-08-09"
  #   "@today-1w" ==> "2024-08-01"
  #
  # @param query String in which to replace references to @today
  # @param timezone Optional timezone to which @today is relative. This can be used to ensure that
  #   today is interpreted appropriately for the viewer's timezone.
  # @param default_time_unit Optional unit to use as a default if the number in an arithmetic expression
  #   omits a unit (e.g. "@today+30"). Valid
  sig do
    params(
      query: String,
      timezone: T.nilable(ActiveSupport::TimeZone),
      default_time_unit: T.nilable(TimeUnit)
    )
    .returns(String)
  end
  def replace_today_macro(query, timezone: nil, default_time_unit: nil)
    query.gsub(/@today([+-]?)(\d*)([dwmy]?)/) do
      date = Time.now.in_time_zone(timezone).to_date
      operator = $1
      number = $2.to_i
      unit = TimeUnit.try_deserialize($3.presence || default_time_unit&.serialize)
      sign = operator == "+" ? 1 : -1

      case unit
      when TimeUnit::Day
        date += sign * number
      when TimeUnit::Week
        date += sign * number * 7
      when TimeUnit::Month
        date >>= number if operator == "+"
        date <<= number if operator == "-"
      when TimeUnit::Year
        date >>= sign * number * 12
      end

      date.strftime("%Y-%m-%d")
    end
  end
end
