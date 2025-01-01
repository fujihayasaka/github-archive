# typed: true
# frozen_string_literal: true

module Newsies
  module SloHelper
    # Finds a tag for the metric that buckets its timing values.
    #
    # This is used because we cannot create a tag for every unique value of time_to_sent_ms. Instead,
    # this buckets the values so we can estimate distributions.
    #
    # buckets - Hash<Integer, String> where keys are the upper bound in milliseconds of the bucket
    #   and values are the datadog tag to apply to that bucket.
    # duration_ms - Integer value (in milliseconds) of the measurement to bucket.
    #
    # Return String for the tag to apply to the measurement.
    def slo_bucket_tag(buckets, duration_ms)
      buckets.find { |(upper_bound_ms, _datadog_tag)| duration_ms <= upper_bound_ms }.second
    end
  end
end
