# typed: strict
# frozen_string_literal: true

# Business::PassThroughCache helps with caching values in GitHub.cache (memcached).
#
# Usage example:
#
#   pc = Business::PassThroughCache.new("my-cache", Time.now.to_i, org.id)
#
#   ids = pc.ids("suspended") do
#     org.members.suspended.pluck(:user_ids)
#   end
#
#   names = pc.values("logins") do
#     org.members.pluck(:login)
#   end
#
#   pc.set("strings", ["a", "b"])
#   pc.get("strings")
#
#   pc.set("ints", [1, 2, 3], :int)
#   pc.get("ints", :int)
#
#   pc.clear(["suspended", "logins", "strings", "ints"])
#
class Business::PassThroughCache
  include GitHub::Memoizer
  extend T::Sig

  class LargeCacheSetError < ::StandardError; end

  CacheValues = T.type_alias { T.any(T::Array[String], T::Array[Integer]) }

  sig do
    params(key_prefix: String, seed: Integer, key_id: T.nilable(Integer), disabled: T::Boolean, expiration: ActiveSupport::Duration, context: T.nilable(T::Hash[T.untyped, T.untyped]), lock_write: T::Boolean).void
  end
  def initialize(key_prefix, seed, key_id = nil, disabled: false, expiration: 1.hour, context: nil, lock_write: true)
    @key_prefix = T.let(key_prefix, String)
    @seed = T.let(seed, Integer)
    @key_id = T.let(key_id || 0, Integer)
    @disabled = T.let(disabled, T::Boolean)
    @expiration = T.let(expiration, ActiveSupport::Duration)
    @context = T.let(context || {}, T::Hash[T.untyped, T.untyped])
    @lock_write = T.let(lock_write, T::Boolean)
  end

  # Public: Create a Restraint Lock for a cache key.
  #
  # Returns the result of the provided block
  sig do
    type_parameters(:R)
      .params(ttl: Integer, key: String, block: T.proc.params(arg0: GitHub::Restraint::Lock).returns(T.type_parameter(:R)))
      .returns(T.type_parameter(:R))
  end
  def lock!(ttl, key: "lock", &block)
    restraint.lock! cache_key(key, skip_seed: true), 1, ttl, &block
  end

  # Public: Stores an array of value in the cache
  #
  # key     - String key for the value to be stored
  # values  - An Array of values to be stored
  # type    - (optioal) A type to be used for storing the values. Can be :int, defaults to
  #           :string
  sig { params(key: String, values: CacheValues, type: T.nilable(Symbol)).void }
  def set(key, values, type = nil)
    k = cache_key(key)
    v = value_coder(type).encode(values)
    if v.bytesize > GitHub::Cache::Failover::MAX_VALUE_SIZE
      begin
        raise LargeCacheSetError
      rescue LargeCacheSetError => error
        # The exception is logged silently to GitHub.logger, but execution still continues
        GitHub.logger.error({
          exception: error,
          cache_key: key,
          cache_set_size: v.size,
          cache_set_type: (type || "string").to_s,
          value_count: values.size
        }.merge(@context))
      end
    end
    GitHub.cache.set(k, v, @expiration)
  end

  # Public: Loads an array of values from the cache
  #
  # key     - String key for the stored value
  # type    - (optioal) A type to be used for loading the values. Can be :int, defaults to
  #           :string
  #
  # Returns an Array of Strings or Integers or nil if nothing is stored in the cache
  sig { params(key: String, type: T.nilable(Symbol)).returns(T.nilable(CacheValues)) }
  def get(key, type = nil)
    k = cache_key(key)
    cached = GitHub.cache.get(k)
    cache_status = cached.nil? ? "miss" : "hit"
    GitHub.logger.info({
      cache_key: key,
      cache_status: cache_status,
      key_id: @key_id,
      "code.namespace": self.class.name,
      "code.function": __method__,
    })
    GitHub.dogstats.increment("pass_through_cache.#{@key_prefix}.get", tags: ["cache_status:#{cache_status}"])
    return nil if cached.nil?
    value_coder(type).decode(cached)
  end

  # Public: Pass-through cache a string array
  #
  # Returns an Array of Strings
  sig { params(key: String, type: T.nilable(Symbol), skip_cache: T.nilable(T::Boolean), block: T.proc.returns(CacheValues)).returns(T.nilable(CacheValues)) }
  def values(key, type = nil, skip_cache: false, &block)
    return yield if @disabled
    unless skip_cache
      cached = get(key, type)
      return cached if cached
    end
    values = yield
    return values if skip_cache
    if @lock_write
      begin
        lock! 5.seconds, key: key do
          set(key, values, type)
        end
      rescue GitHub::Restraint::UnableToLock
        # Fail silently when another process has already locked the cache
      end
    else
      set(key, values, type)
    end
    values
  end

  # Public Pass-through caching optimized for storing and array of integer ids.
  # The ids will be stored in binary form.
  #
  # Returns an Array of Integers
  sig { params(key: String,  skip_cache: T.nilable(T::Boolean), block: T.proc.returns(CacheValues)).returns(T.nilable(T::Array[Integer])) }
  def ids(key, skip_cache: false, &block)
    values(key, :int, skip_cache: skip_cache, &block)&.map(&:to_i)
  end

  sig { returns(T::Boolean) }
  def disabled?
    @disabled
  end

  private

  # Private: Generate a cache key from the prefix, id and provided key
  #
  # Returns an Integer
  sig { params(key: String, skip_seed: T.nilable(T::Boolean)).returns(String) }
  def cache_key(key, skip_seed: false)
    [@key_prefix, "cache", skip_seed ? nil : @seed, @key_id, key].compact.join("-")
  end

  # Private: Select a ValueCoder for the type
  #
  # Returns a ValueCoder
  sig { params(type: T.nilable(Symbol)).returns(ValueCoder) }
  def value_coder(type)
    return IntValueCoder.new if type == :int
    ValueCoder.new
  end

  sig { returns(GitHub::Restraint) }
  memoize def restraint
    GitHub::Restraint.new
  end

  class ValueCoder
    extend T::Sig

    sig { params(values: CacheValues).returns(String) }
    def encode(values)
      values.map(&:to_s).join(",")
    end

    sig { params(values: String).returns(CacheValues) }
    def decode(values)
      values.split(",")
    end
  end

  class IntValueCoder < ValueCoder
    sig { params(values: CacheValues).returns(String) }
    def encode(values)
      values.map(&:to_i).map { |i| [i].pack("Q<") }.join("")
    end

    sig { params(values: String).returns(CacheValues) }
    def decode(values)
      values.unpack("Q<*").map(&:to_i).compact
    end
  end
end
