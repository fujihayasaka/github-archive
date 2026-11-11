# typed: true
# frozen_string_literal: true

module RecurringMailer
  extend ActiveSupport::Concern

  class Error < StandardError; end

  module ClassMethods
    # Determines the time and date that the next newsletter should be delivered.
    # This takes into account user's timezones and the type of newsletter
    # (period) being delivered.
    #
    # Daily emails go out at 9am.
    # Weekly emails go out at 9am Tuesday.
    # Fortnightly emails go out at 9am every other Tuesday.
    # Monthly emails go out at 9am on the 1st.
    #
    # Returns a DateTime.
    def next_delivery_for(user, period = "weekly")
      # Start today at midnight (that would be in the past)
      deliver_at = DateTime.now.in_time_zone(user.time_zone).midnight

      case period
      when "daily", "one_off"
        deliver_at += 1.day
      when "weekly"
        deliver_at = deliver_at.beginning_of_week + 1.day
        deliver_at += 7.days if deliver_at <= Time.now
      when "monthly"
        deliver_at = deliver_at.beginning_of_month
        deliver_at += 1.month if deliver_at <= Time.now
      else
        err = StandardError.new("Invalid newsletter subscription range: #{period}")
        Failbot.report(err, user: user)
      end

      deliver_at.change(hour: 9).utc
    end
  end
end
