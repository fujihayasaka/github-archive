# typed: strict
# frozen_string_literal: true

Time::DATE_FORMATS[:bold] = "%d %B %Y"
Time::DATE_FORMATS[:git] = -> (time) { time.strftime("@#{time.to_i} %z") }
Time::DATE_FORMATS[:date] = "%F"
Time::DATE_FORMATS[:zuora_usage_file] = "%m/%d/%Y"
Time::DATE_FORMATS[:eventer] = "%Y-%m-%dT%H:%M:%S"
Time::DATE_FORMATS[:deprecation_mailer] = -> (time) { day_format = ActiveSupport::Inflector.ordinalize(time.day); time.strftime("%B #{day_format}, %Y at %H:%M (%Z)") }
Time::DATE_FORMATS[:aria_label_time_today] = "%I:%M%p today"
Time::DATE_FORMATS[:aria_label_time_yesterday] = "%I:%M%p yesterday"
Time::DATE_FORMATS[:aria_label_time_month_day] = "%I:%M%p on %B %d"
Time::DATE_FORMATS[:aria_label_time_month_day_year] = "%I:%M%p on %B %d, %Y"

Date::DATE_FORMATS[:date] = "%F"
