# typed: true
# frozen_string_literal: true

module Eventer
  module TimeBucket
    BUCKET_SIZE_DAY = :DAY
    BUCKET_SIZE_HOUR = :HOUR

    # Default build time bucket of DAY if bucket.size is not specified
    def self.build(bucket)
      return unless bucket[:timestamp]

      if bucket[:size] == BUCKET_SIZE_HOUR
        return build_hour_bucket(bucket[:timestamp])
      end
      build_day_bucket(bucket[:timestamp])
    end

    # private
    def self.build_day_bucket(timestamp)
      return unless timestamp

      start = Time.utc(timestamp.year, timestamp.month, timestamp.day)

      {
        start: start,
        size: :DAY,
      }
    end

    # private
    def self.build_hour_bucket(timestamp)
      return unless timestamp

      start = Time.utc(timestamp.year, timestamp.month, timestamp.day, timestamp.hour)

      {
        start: start,
        size: :HOUR,
      }
    end
    private_class_method :build_day_bucket
    private_class_method :build_hour_bucket
  end
end
