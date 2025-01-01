# typed: true
# frozen_string_literal: true

module BlackbirdSearch
  module Redis
    extend self
    extend T::Sig

    sig do
      params(
        key: String,
        value: String,
        expire_sec: Integer, # Expire time in seconds
      ).returns(GitHub::KV::Result)
    end
    def set(key:, value:, expire_sec:)
      # https://github.com/redis/redis-rb/blob/v4.1.0/lib/redis.rb#L772-L781
      GitHub::Result.new { redis_instance.set(key, value, { ex: expire_sec }) == "OK" }
    end

    sig do
      type_parameters(:T)
      .params(
        key: String
      ).returns(GitHub::KV::Result)
    end
    def get(key:)
      GitHub::Result.new { redis_instance.get(key) }
    end

    sig do
      params(
        keys: T::Array[String]
      ).returns(GitHub::KV::Result)
    end
    def del(keys:)
      GitHub::Result.new { redis_instance.del(keys) }
    end

    sig { params(key: String, timeout_sec: Integer).returns(GitHub::Redis::ConcurrencySafeMutex) }
    def mutex(key:, timeout_sec:)
      GitHub::Redis::ConcurrencySafeMutex.new(key, timeout: timeout_sec, redis: redis_instance)
    end

    sig { returns(::Redis) }
    def redis_instance
      @blackbird_redis ||= T.let(::Redis.new(GitHub.read_redis_config("config/redis_blackbird.yml")), T.nilable(::Redis))
    end
  end
end
