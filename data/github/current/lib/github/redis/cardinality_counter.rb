# typed: true
# frozen_string_literal: true

module GitHub
  module Redis
    # A class to compute cardinality counts during adjustable time ranges.
    class CardinalityCounter
      # We automatically trim any key with a score older than 90 days.
      MAX_LOOKBACK_TIME = 90.days

      attr_reader :redis, :domain

      # domain - a string identifying this group of things to be counted
      # redis - a Redis instance.
      def initialize(domain:, redis: ::Redis::Namespace.new(:resque, redis: GitHub.job_coordination_redis))
        @domain = domain
        @redis = redis
      end

      # A key pointing to a redis sorted set whose keys are the hex representation
      # of the SHA-1 hash of the `to_s` representation of the objects being counted
      # and the scores are floating point epoch timestamps.
      def key
        @key ||= "cardinality_counter:#{domain}"
      end

      def count(since:)
        redis.zcount(key, since.to_f, "+inf")
      end

      # Remove old keys so our set doesn't grow unbounded.
      def trim
        trim_before = (Time.current - MAX_LOOKBACK_TIME).to_f
        redis.zremrangebyscore(key, "-inf", trim_before)
      end

      def add(item)
        key_name = item.to_s
        if key_name.size > 128 # avoid storing really long strings
          hash = Digest::SHA256.hexdigest(key_name)
          key_name = "#{key_name[0..63]}#{hash}"
        end
        redis.pipelined do
          trim
          redis.zadd(key, Time.current.to_f, key_name)
        end
      end
    end
  end
end
