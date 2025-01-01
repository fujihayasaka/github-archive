# typed: false
# frozen_string_literal: true

module ReminderScheduling
  extend ActiveSupport::Concern

  included do
    has_many :delivery_times, as: :schedulable, class_name: "ReminderDeliveryTime", dependent: :destroy
    accepts_nested_attributes_for :delivery_times, allow_destroy: true, reject_if: :incomplete_or_duplicate_delivery_time_attributes?

    validates :time_zone_name, presence: true
    validate :validate_time_zone_name
    validate :validate_duplicate_delivery_times
  end

  def self.timezone_options
    TZInfo::DataTimezone.all.map(&:name).map do |name|
      ActiveSupport::TimeZone[name]
    end
  end

  def self.timezone_for(name)
    return if name.blank?
    timezone = ActiveSupport::TimeZone[name]
    return unless timezone

    tzinfo_name = timezone.tzinfo.name
    timezone_options.find do |timezone|
      timezone.tzinfo.name == tzinfo_name
    end
  end

  def self.valid_time_zone_name?(name)
    !!timezone_for(name)
  end

  def validate_time_zone_name
    return if time_zone_name.blank?
    return if ReminderScheduling.valid_time_zone_name?(time_zone_name)

    errors.add(:time_zone_name, "not supported (#{time_zone_name.inspect})")
  end

  def incomplete_or_duplicate_delivery_time_attributes?(attributes)
    return true if attributes["day"].nil? || attributes["time"].nil?

    delivery_times.find do |delivery_time|
      delivery_time.day == attributes["day"] && delivery_time.time == attributes["time"]
    end
  end

  def mark_delivery_times_for_destruction(exclude:)
    generate_record_key = -> (hash) { hash.slice("day", "time").values.join("-") }
    record_keys_to_keep = exclude.map(&generate_record_key)

    delivery_times.each do |delivery_time|
      record_key = generate_record_key.call(delivery_time)
      next if record_keys_to_keep.include?(record_key)

      delivery_time.mark_for_destruction
    end
  end

  def delivery_times_attributes=(attributes)
    mark_delivery_times_for_destruction(exclude: attributes)
    super(attributes)
  end

  def times
    delivery_times.map(&:time).uniq
  end

  def days
    delivery_times.map(&:day).uniq
  end

  def delivery_days_text
    if weekdays?
      "Weekdays"
    elsif weekends?
      "Weekends"
    elsif every_day?
      "Every day"
    elsif !days.empty?
      days.map { |d| d[0..2] }.to_sentence(last_word_connector: ", ")
    end
  end

  def delivery_times_text
    return unless delivery_times.present?

    "#{delivery_days_text} at #{times.join(", ")} #{time_zone_abbreviation}"
  end

  def time_zone_abbreviation
    time_zone = ReminderScheduling.timezone_for(time_zone_name)
    return "" unless time_zone

    zone_name = time_zone.tzinfo.current_period.abbreviation
    if zone_name.to_s.start_with?("-", "+")
      # If we get here, we had no entry for the time zone
      # We can take the tzinfo name, which may be something like Etc/GMT+12
      # We want to remove the Etc/ for show, because it just means "other" timezones and is a POSIX thing
      zone_name = time_zone.tzinfo.name.dup.tr("Etc/", "")
    end

    zone_name
  end

  def weekdays?
    days == %w[Monday Tuesday Wednesday Thursday Friday]
  end

  def weekends?
    days == %w[Saturday Sunday]
  end

  def every_day?
    days == %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday]
  end

  def update_next_delivery_times(now: nil)
    delivery_times.map { |delivery_time| delivery_time.update_next_delivery_at(now: now) }
  end

  def validate_duplicate_delivery_times
    day_and_times = delivery_times.map { |delivery_time| delivery_time.slice("day", "time") }
    if day_and_times.uniq.length != delivery_times.length
      self.errors.add(:delivery_times, "must be unique")
    end
  end

  def valid_delivery_at?(delivery_at)
    delivery_times.where(next_delivery_at: delivery_at).exists?
  end

  def serialize_delivery_times
    delivery_times.reduce({ days: [], times: [] }) do |delivery_times_hash, time|
      delivery_times_hash[:days].push(time.day) unless delivery_times_hash[:days].include?(time.day)
      delivery_times_hash[:times].push(time.time) unless delivery_times_hash[:times].include?(time.time)
      delivery_times_hash
    end
  end
end
