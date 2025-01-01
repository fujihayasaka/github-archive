# typed: strict
# frozen_string_literal: true

module Copilot
  class LimiterRedis
    # Get the value of a key.
    #
    # @param key [String]
    # @return [String] the value of the key, or nil when the key does not exist.
    sig { params(key: String).returns(T.nilable(String)) }
    def self.get(key)
      GitHub.logger.with_named_tags({
        "code.function": "get",
        "code.namespace": self.class.name,
        "gh.copilot.limited_user.key": key,
      }) do
        if circuit_breaker.allow_request?
          GitHub.logger.info("Circuit is closed, allowing request")
          begin
            value = Copilot.limiter_redis.get(key)
            GitHub.dogstats.increment("copilot.limiter_redis_event", tags: ["method:get", "success:true"])
            circuit_breaker.success
            value
          rescue => e # rubocop:todo Lint/GenericRescue
            GitHub.logger.error("Error getting key from redis", {
              exception: e,
            })
            GitHub.dogstats.increment("copilot.limiter_redis_event", tags: ["method:get", "success:false"])
            circuit_breaker.failure
            nil
          end
        else
          GitHub.logger.info("Circuit is open, not allowing request")
          nil
        end
      end
    end

    # Get the values of all the given keys.
    #
    # @example
    #   redis.mapped_mget("key1", "key2")
    #   # => { "key1" => "v1", "key2" => "v2" }
    # @param keys [Array<String>] array of keys
    # @return [Hash] a hash mapping the specified keys to their values
    # @see #mget
    #
    # source://redis//lib/redis.rb#937
    sig { params(keys: T::Array[String]).returns(T::Hash[String, String]) }
    def self.mget(keys)
      GitHub.logger.with_named_tags({
        "code.function": "mget",
        "code.namespace": self.class.name,
        "gh.copilot.limited_user.keys": keys,
      }) do
        if circuit_breaker.allow_request?
          GitHub.logger.info("Circuit is closed, allowing request")
          begin
            value = T.unsafe(Copilot.limiter_redis).mapped_mget(*keys).map do |k, v|
              # if the value is nil, set it to 0
              v = "0" if v.nil?
              [k.to_s, v]
            end.to_h

            GitHub.dogstats.increment("copilot.limiter_redis_event", tags: ["method:mget", "success:true"])

            circuit_breaker.success

            value
          rescue => e # rubocop:todo Lint/GenericRescue
            GitHub.logger.error("Error getting key from redis", {
              exception: e,
            })
            GitHub.dogstats.increment("copilot.limiter_redis_event", tags: ["method:mget", "success:false"])
            circuit_breaker.failure
            keys.map do |key|
              [key.to_s, "0"]
            end
          end
        else
          GitHub.logger.info("Circuit is open, not allowing request")
          keys.map do |key|
            [key.to_s, "0"]
          end.to_h
        end
      end
    end

    # Set the string value of a hash field.
    #
    # @param key [String]
    # @param field [String]
    # @param value [String]
    # @return [Boolean] whether or not the field was **added** to the hash
    sig { params(key: String, field: String, value: T.any(Integer, String)).returns(T::Boolean) }
    def self.hset(key, field, value)
      GitHub.logger.with_named_tags({
        "code.function": "hset",
        "code.namespace": self.class.name,
        "gh.copilot.limited_user.key": key,
        "gh.copilot.limited_user.field": field,
        "gh.copilot.limited_user.value": value,
      }) do
        if circuit_breaker.allow_request?
          GitHub.logger.info("Circuit is closed, allowing request")
          begin
            returnvalue = Copilot.limiter_redis.hset(key, field, value)
            GitHub.dogstats.increment("copilot.limiter_redis_event", tags: ["method:hset", "success:true"])
            circuit_breaker.success
            returnvalue
          rescue => e # rubocop:todo Lint/GenericRescue
            GitHub.logger.error("Error setting hash to redis", {
              exception: e,
            })
            GitHub.dogstats.increment("copilot.limiter_redis_event", tags: ["method:hset", "success:false"])
            circuit_breaker.failure
            false
          end
        else
          GitHub.logger.info("Circuit is open, not allowing request")
          false
        end
      end
    end

    # Set the string value of a key.
    #
    # @param key [String]
    # @param value [String]
    # @param options [Hash] - `:ex => Fixnum`: Set the specified expire time, in seconds.
    #   - `:px => Fixnum`: Set the specified expire time, in milliseconds.
    #   - `:nx => true`: Only set the key if it does not already exist.
    #   - `:xx => true`: Only set the key if it already exist.
    # @return [String, Boolean] `"OK"` or true, false if `:nx => true` or `:xx => true`
    sig do
      params(
        key: String,
        value: T.any(Integer, String),
        options: T::Hash[Symbol, T.any(Integer, T::Boolean)],
      ).returns(T.any(String, T::Boolean))
    end
    def self.set(key, value, options = {})
      GitHub.logger.with_named_tags({
        "code.function": "set",
        "code.namespace": self.class.name,
        "gh.copilot.limited_user.key": key,
        "gh.copilot.limited_user.value": value,
        "gh.copilot.limited_user.options": options,
      }) do
        if circuit_breaker.allow_request?
          GitHub.logger.info("Circuit is closed, allowing request")
          begin
            returnvalue = Copilot.limiter_redis.set(key, value)
            GitHub.dogstats.increment("copilot.limiter_redis_event", tags: ["method:set", "success:true"])
            circuit_breaker.success
            returnvalue
          rescue => e # rubocop:todo Lint/GenericRescue
            GitHub.logger.error("Error setting hash to redis", {
              exception: e,
            })
            GitHub.dogstats.increment("copilot.limiter_redis_event", tags: ["method:set", "success:false"])
            circuit_breaker.failure
            false
          end
        else
          GitHub.logger.info("Circuit is open, not allowing request")
          false
        end
      end
    end

    sig { returns(Resilient::CircuitBreaker) }
    private_class_method def self.circuit_breaker
      options = {
        # seconds after tripping circuit before allowing retry
        sleep_window_seconds: 5,
        # number of requests that must be made within a statistical window
        # before open/close decisions are made using stats
        request_volume_threshold: 5,
        # % of "marks" that must be failed to trip the circuit
        error_threshold_percentage: 50,
        # number of seconds in the statistical window
        window_size_in_seconds: 30,
        # size of buckets in statistical window
        bucket_size_in_seconds: 5,
      }

      options[:instrumenter] = GitHub if GitHub.respond_to?(:instrument)

      Resilient::CircuitBreaker.get("copilot_limiter_redis", options)
    end
  end
end
