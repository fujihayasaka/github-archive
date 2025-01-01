
# typed: strict
# frozen_string_literal: true

module Repositories
  module Redis
    extend self
    extend T::Sig

    sig do
      params(
        key: String,
        value: String,
        px: Integer,
        nx: T.nilable(T::Boolean),
        xx: T.nilable(T::Boolean)
      ).returns(T::Boolean)
    end
    def set!(key:, value:, px:, nx: nil, xx: nil)
      # https://github.com/redis/redis-rb/blob/v4.1.0/lib/redis.rb#L772-L781
      result = redis_instance.set(key, value, { px:, nx:, xx: }.compact_blank)

      return true if result == "OK"

      result
    end

    sig do
      params(
        key: String,
        value: String,
        px: Integer,
        nx: T.nilable(T::Boolean),
        xx: T.nilable(T::Boolean)
      ).returns(T::Boolean)
    end
    def set(key:, value:, px:, nx: nil, xx: nil)
      GitHub::Result.new { set!(key:, value:, px:, nx:, xx:) }.value { false }
    end

    sig do
      params(
        key: String
      ).returns(T.nilable(String))
    end
    def get!(key:)
      redis_instance.get(key)
    end

    sig do
      type_parameters(:T)
      .params(
        key: String,
        fallback: T.nilable(T.all(Object, T.any(
          T.proc.returns(T.type_parameter(:T)),
          T.type_parameter(:T),
        ))),
      ).returns(T.nilable(T.any(String, T.type_parameter(:T))))
    end
    def get(key:, fallback: nil)
      handle_with_fallback(fallback:) { get!(key:) }
    end

    sig do
      params(
        keys: T::Array[String]
      ).returns(Integer)
    end
    def del!(keys:)
      redis_instance.del(keys)
    end

    sig do
      type_parameters(:T)
      .params(
        keys: T::Array[String],
        fallback: T.nilable(T.all(Object, T.any(
          T.proc.returns(T.type_parameter(:T)),
          T.type_parameter(:T),
        ))),
      ).returns(T.nilable(T.any(Integer, T.type_parameter(:T))))
    end
    def del(keys:, fallback: nil)
      handle_with_fallback(fallback:) { del!(keys:) }
    end

    sig { params(key: String, timeout_sec: Integer).returns(GitHub::Redis::ConcurrencySafeMutex) }
    def mutex(key:, timeout_sec:)
      GitHub::Redis::ConcurrencySafeMutex.new(key, timeout: timeout_sec, redis: redis_instance)
    end

    sig { returns(::Redis) }
    def redis_instance
      @repos_redis ||= T.let(::Redis.new(GitHub.read_redis_config("config/redis_repos.yml")), T.nilable(::Redis))
    end

    private

    sig do
      type_parameters(:T)
      .params(
        fallback: T.nilable(T.all(Object, T.any(
          T.proc.returns(T.type_parameter(:T)),
          T.type_parameter(:T),
        ))),
        blk: T.proc.returns(T.type_parameter(:T)),
      ).returns(T.nilable(T.type_parameter(:T)))
    end
    def handle_with_fallback(fallback: nil, &blk)
      result = GitHub::Result.new(&blk)

      fallback&.respond_to?(:call) ? T.unsafe(fallback).call : fallback
      if fallback
        return result.value { T.unsafe(fallback).call } if fallback.respond_to?(:call)
        return result.value { fallback }
      end

      result.value { nil }
    end

  end
end
