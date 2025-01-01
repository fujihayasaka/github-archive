# typed: true
# frozen_string_literal: true

class ReminderDeliveryTime < ApplicationRecord::Collab
  belongs_to :schedulable, polymorphic: true

  validates_presence_of :day, :time, :schedulable

  # Records with delivery in the next n minutes (defaults to 10)
  scope :upcoming, -> (before: 10.minutes.from_now) { where("next_delivery_at < ?", before) }

  BROKEN_TIME_ZONES = {
    "US/Pacific-New" => "US/Pacific",
    "SystemV/PST8" => "US/Pacific",
    "SystemV/CST6CDT" => "US/Central",
    "SystemV/MST7" => "US/Mountain",
    "SystemV/CST6" => "US/Central",
  }

  WEEKDAYS = {
    "Monday" => 1,
    "Tuesday" => 2,
    "Wednesday" => 3,
    "Thursday" => 4,
    "Friday" => 5,
  }
  WEEKENDS = {
    "Saturday" => 6,
    "Sunday" => 7,
  }

  enum :day, WEEKDAYS.merge(WEEKENDS)

  enum :time, {
    "12:00 AM" => 1, "5:00 AM" => 11, "10:00 AM" => 21, "3:00 PM" => 31, "8:00 PM" => 41,
    "12:30 AM" => 2, "5:30 AM" => 12, "10:30 AM" => 22, "3:30 PM" => 32, "8:30 PM" => 42,
    "1:00 AM" => 3,  "6:00 AM" => 13, "11:00 AM" => 23, "4:00 PM" => 33, "9:00 PM" => 43,
    "1:30 AM" => 4,  "6:30 AM" => 14, "11:30 AM" => 24, "4:30 PM" => 34, "9:30 PM" => 44,
    "2:00 AM" => 5,  "7:00 AM" => 15, "12:00 PM" => 25, "5:00 PM" => 35, "10:00 PM" => 45,
    "2:30 AM" => 6,  "7:30 AM" => 16, "12:30 PM" => 26, "5:30 PM" => 36, "10:30 PM" => 46,
    "3:00 AM" => 7,  "8:00 AM" => 17, "1:00 PM" => 27,  "6:00 PM" => 37, "11:00 PM" => 47,
    "3:30 AM" => 8,  "8:30 AM" => 18, "1:30 PM" => 28,  "6:30 PM" => 38, "11:30 PM" => 48,
    "4:00 AM" => 9,  "9:00 AM" => 19, "2:00 PM" => 29,  "7:00 PM" => 39,
    "4:30 AM" => 10, "9:30 AM" => 20, "2:30 PM" => 30,  "7:30 PM" => 40
  }

  HOUR_AND_MINUTE = {
    "12:00 AM" => [0, 0],  "5:00 AM" => [5, 0],  "10:00 AM" => [10, 0],  "3:00 PM" => [15, 0],  "8:00 PM" => [20, 0],
    "12:30 AM" => [0, 30], "5:30 AM" => [5, 30], "10:30 AM" => [10, 30], "3:30 PM" => [15, 30], "8:30 PM" => [20, 30],
     "1:00 AM" => [1, 0],  "6:00 AM" => [6, 0],  "11:00 AM" => [11, 0],  "4:00 PM" => [16, 0],  "9:00 PM" => [21, 0],
     "1:30 AM" => [1, 30], "6:30 AM" => [6, 30], "11:30 AM" => [11, 30], "4:30 PM" => [16, 30], "9:30 PM" => [21, 30],
     "2:00 AM" => [2, 0],  "7:00 AM" => [7, 0],  "12:00 PM" => [12, 0],  "5:00 PM" => [17, 0],  "10:00 PM" => [22, 0],
     "2:30 AM" => [2, 30], "7:30 AM" => [7, 30], "12:30 PM" => [12, 30], "5:30 PM" => [17, 30], "10:30 PM" => [22, 30],
     "3:00 AM" => [3, 0],  "8:00 AM" => [8, 0],  "1:00 PM" => [13, 0],   "6:00 PM" => [18, 0],  "11:00 PM" => [23, 0],
     "3:30 AM" => [3, 30], "8:30 AM" => [8, 30], "1:30 PM" => [13, 30],  "6:30 PM" => [18, 30], "11:30 PM" => [23, 30],
     "4:00 AM" => [4, 0],  "9:00 AM" => [9, 0],  "2:00 PM" => [14, 0],   "7:00 PM" => [19, 0],
     "4:30 AM" => [4, 30], "9:30 AM" => [9, 30], "2:30 PM" => [14, 30],  "7:30 PM" => [19, 30]
  }

  before_create :set_next_delivery_at # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  def set_next_delivery_at(now: time_zone.now)
    self.next_delivery_at = calculate_next_delivery_time(now: now)
  end

  def update_next_delivery_at(now: nil)
    set_next_delivery_at(now: now)
    save
  end

  def calculate_next_delivery_time(now: nil)
    # Always interpret `now` in the schedulable's timezone. If a UTC Time is
    # passed in (e.g., from a job using a delivery target), convert it to the
    # appropriate TimeWithZone first to avoid scheduling at UTC instead of the
    # user's local time.
    local_now = (now || time_zone.now).in_time_zone(time_zone)
    hour, minute = hour_and_minute
    next_time = local_now.change(hour: hour, min: minute)

    if delivery_day_of_week?(next_time) && next_time > local_now
      next_time
    else
      next_time.next_occurring(day.downcase.to_sym)
    end
  end

  def time_zone
    ReminderScheduling.timezone_for(time_zone_name) || raise("Time zone not found for value: #{time_zone_name.inspect}")
  end

  def time_zone_name
    stored_tz_name = schedulable&.time_zone_name
    if FeatureFlag.vexi.enabled?(:schedule_reminders_time_zone_correction, default: true) && BROKEN_TIME_ZONES.include?(stored_tz_name)
      GitHub.logger.info("Time zone correction", {
        "gh.scheduled_reminders.timezone" => stored_tz_name,
        "gh.scheduled_reminders.remindable.type" => schedulable&.remindable_type || "",
        "gh.scheduled_reminders.remindable.id" => schedulable&.remindable_id || ""
      })
      BROKEN_TIME_ZONES[stored_tz_name]
    else
      stored_tz_name
    end
  end

  # True when time is on delivery day of week for this record.
  private def delivery_day_of_week?(time)
    self.class.days.key(time.wday) == day
  end

  # Split #time into hour (0-24) and minute (0-60).
  # For example, "7:30 PM" becomes `[19, 30]`
  def hour_and_minute
    raise "Time not set" if time.nil?

    HOUR_AND_MINUTE.fetch(time)
  end
end
