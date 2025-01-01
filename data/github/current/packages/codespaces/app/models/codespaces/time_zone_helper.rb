# typed: true
# frozen_string_literal: true

module Codespaces
  class TimeZoneHelper

    def self.get_time_zone(time_zone_name:)
      return if time_zone_name.blank?
      timezone = ActiveSupport::TimeZone[time_zone_name]
      return unless timezone

      tzinfo_name = timezone.tzinfo.name
      timezone_options.find do |timezone|
        timezone.tzinfo.name == tzinfo_name
      end
    end

    def self.timezone_options
      TZInfo::DataTimezone.all.map(&:name).map do |name|
        ActiveSupport::TimeZone[name]
      end
    end

  end
end
