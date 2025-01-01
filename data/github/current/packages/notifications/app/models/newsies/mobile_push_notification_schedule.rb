# typed: true
# frozen_string_literal: true

module Newsies
  class MobilePushNotificationSchedule < ApplicationRecord::Domain::Notifications
    self.utc_datetime_columns = %i[created_at updated_at]

    belongs_to :user, required: true

    validates :day, presence: true, uniqueness: { scope: :user_id }
    validate :start_time_format
    validate :end_time_format

    # based off of Time#wday which uses a 0-6 range, with 0 being sunday
    WDAY = {
      0 => :sunday,
      1 => :monday,
      2 => :tuesday,
      3 => :wednesday,
      4 => :thursday,
      5 => :friday,
      6 => :saturday,
    }

    enum :day, WDAY.invert

    def self.deliver_to_user?(user)
      return false unless user
      return true unless exists?(user: user)

      user_push_settings = MobilePushNotificationSetting.find_by(user_id: user.id)
      return true unless user_push_settings
      return true unless user_push_settings.scheduled_notifications?

      Time.use_zone(user.mobile_time_zone) do
        now = Time.zone.now
        schedule = find_by(day: now.wday, user_id: user.id)
        return false unless schedule
        return false unless schedule.start_time && schedule.end_time

        return now >= Time.zone.strptime(schedule.start_time, "%H:%M") &&
          now <= Time.zone.strptime(schedule.end_time, "%H:%M")
      end
    end

    private

    def start_time_format
      return unless start_time.present?

      Time.strptime(start_time, "%H:%M")
    rescue ArgumentError, TypeError
      errors.add :start_time, "is invalid"
    end

    def end_time_format
      return unless end_time.present?

      Time.strptime(end_time, "%H:%M")
    rescue ArgumentError, TypeError
      errors.add :end_time, "is invalid"
    end
  end
end
